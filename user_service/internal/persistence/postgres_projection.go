package persistence

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"user_service/internal/domain"
)

func (r *PostgresRepository) ListCalculations(ctx context.Context, tenant, userID string, page Page) ([]domain.CalculationProjection, error) {
	rows, err := r.db.QueryContext(ctx, `
select tenant,calculation_id,user_id,coalesce(operation,''),coalesce(expression,''),operands,coalesce(result,''),status,coalesce(error_message,''),coalesce(source_event_id,''),occurred_at,metadata,coalesce(s3_object_key,''),created_at,updated_at
from user_calculation_projections where tenant=$1 and user_id=$2 and deleted_at is null
order by occurred_at desc limit $3 offset $4`, tenant, userID, page.Limit, page.Offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.CalculationProjection{}
	for rows.Next() {
		c, err := scanCalculation(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (r *PostgresRepository) GetCalculation(ctx context.Context, tenant, userID, calculationID string) (domain.CalculationProjection, error) {
	row := r.db.QueryRowContext(ctx, `
select tenant,calculation_id,user_id,coalesce(operation,''),coalesce(expression,''),operands,coalesce(result,''),status,coalesce(error_message,''),coalesce(source_event_id,''),occurred_at,metadata,coalesce(s3_object_key,''),created_at,updated_at
from user_calculation_projections where tenant=$1 and user_id=$2 and calculation_id=$3 and deleted_at is null`, tenant, userID, calculationID)
	return scanCalculation(row)
}

func scanCalculation(row interface{ Scan(dest ...any) error }) (domain.CalculationProjection, error) {
	var c domain.CalculationProjection
	var operands, metadata []byte
	if err := row.Scan(&c.Tenant, &c.CalculationID, &c.UserID, &c.Operation, &c.Expression, &operands, &c.Result, &c.Status, &c.ErrorMessage, &c.SourceEventID, &c.OccurredAt, &metadata, &c.S3ObjectKey, &c.CreatedAt, &c.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return domain.CalculationProjection{}, ErrNotFound
		}
		return domain.CalculationProjection{}, err
	}
	c.Operands = emptyJSON(operands, "[]")
	c.Metadata = emptyJSON(metadata, "{}")
	return c, nil
}

func (r *PostgresRepository) ListTodos(ctx context.Context, tenant, userID string, page Page) ([]domain.TodoProjection, error) {
	rows, err := r.db.QueryContext(ctx, `
select tenant,todo_id,user_id,title,coalesce(description,''),status,priority,due_date,tags,completed_at,archived_at,coalesce(source_event_id,''),metadata,created_at,updated_at
from user_todo_projections where tenant=$1 and user_id=$2 and deleted_at is null
order by updated_at desc limit $3 offset $4`, tenant, userID, page.Limit, page.Offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.TodoProjection{}
	for rows.Next() {
		t, err := scanTodo(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

func (r *PostgresRepository) GetTodo(ctx context.Context, tenant, userID, todoID string) (domain.TodoProjection, error) {
	row := r.db.QueryRowContext(ctx, `
select tenant,todo_id,user_id,title,coalesce(description,''),status,priority,due_date,tags,completed_at,archived_at,coalesce(source_event_id,''),metadata,created_at,updated_at
from user_todo_projections where tenant=$1 and user_id=$2 and todo_id=$3 and deleted_at is null`, tenant, userID, todoID)
	return scanTodo(row)
}

func scanTodo(row interface{ Scan(dest ...any) error }) (domain.TodoProjection, error) {
	var t domain.TodoProjection
	var due, completed, archived sql.NullTime
	var tags, metadata []byte
	if err := row.Scan(&t.Tenant, &t.TodoID, &t.UserID, &t.Title, &t.Description, &t.Status, &t.Priority, &due, &tags, &completed, &archived, &t.SourceEventID, &metadata, &t.CreatedAt, &t.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return domain.TodoProjection{}, ErrNotFound
		}
		return domain.TodoProjection{}, err
	}
	if due.Valid {
		t.DueDate = &due.Time
	}
	if completed.Valid {
		t.CompletedAt = &completed.Time
	}
	if archived.Valid {
		t.ArchivedAt = &archived.Time
	}
	t.Tags = emptyJSON(tags, "[]")
	t.Metadata = emptyJSON(metadata, "{}")
	return t, nil
}

func (r *PostgresRepository) TodoSummary(ctx context.Context, tenant, userID string) (map[string]int, error) {
	return countByStatus(ctx, r.db, `select coalesce(status,'UNKNOWN'), count(*) from user_todo_projections where tenant=$1 and user_id=$2 and deleted_at is null group by status`, tenant, userID)
}

func (r *PostgresRepository) ListTodoActivity(ctx context.Context, tenant, userID string, page Page) ([]domain.ActivityEvent, error) {
	rows, err := r.db.QueryContext(ctx, `
select id,tenant,user_id,actor_id,event_type,aggregate_type,aggregate_id,summary,metadata,created_at
from user_activity_events where tenant=$1 and user_id=$2 and aggregate_type='todo' and deleted_at is null
order by created_at desc limit $3 offset $4`, tenant, userID, page.Limit, page.Offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanActivities(rows)
}

func (r *PostgresRepository) applyCalculationProjectionTx(ctx context.Context, tx *sql.Tx, e domain.EventEnvelope) error {
	id := e.AggregateID
	if id == "" {
		id = stringValue(e.Payload, "calculation_id")
	}
	if id == "" {
		return nil
	}
	occurred := time.Now().UTC()
	if t, err := time.Parse(time.RFC3339Nano, e.Timestamp); err == nil {
		occurred = t.UTC()
	}
	status := stringValue(e.Payload, "status")
	if status == "" {
		if strings.Contains(e.EventType, "failed") {
			status = "FAILED"
		} else {
			status = "COMPLETED"
		}
	}
	_, err := tx.ExecContext(ctx, `
insert into user_calculation_projections(tenant,calculation_id,user_id,operation,expression,operands,result,status,error_message,source_event_id,occurred_at,metadata,s3_object_key,created_at,updated_at)
values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,now(),now())
on conflict(tenant,calculation_id) do update set user_id=excluded.user_id,operation=excluded.operation,expression=excluded.expression,operands=excluded.operands,result=excluded.result,status=excluded.status,error_message=excluded.error_message,source_event_id=excluded.source_event_id,occurred_at=excluded.occurred_at,metadata=excluded.metadata,s3_object_key=excluded.s3_object_key,updated_at=now(),deleted_at=null`,
		e.Tenant, id, e.UserID, stringValue(e.Payload, "operation"), stringValue(e.Payload, "expression"), rawValue(e.Payload, "operands", domain.EmptyArray()), stringValue(e.Payload, "result"), status, stringValue(e.Payload, "error_message"), e.EventID, occurred, e.Payload, stringValue(e.Payload, "s3_object_key"))
	if err != nil {
		return err
	}
	return r.insertActivityTx(ctx, tx, eventActivity(e, "calculation projection updated"))
}

func (r *PostgresRepository) applyTodoProjectionTx(ctx context.Context, tx *sql.Tx, e domain.EventEnvelope) error {
	id := e.AggregateID
	if id == "" {
		id = stringValue(e.Payload, "todo_id")
	}
	if id == "" {
		return nil
	}
	status := stringValue(e.Payload, "status")
	if status == "" {
		status = "PENDING"
	}
	priority := stringValue(e.Payload, "priority")
	if priority == "" {
		priority = "MEDIUM"
	}
	_, err := tx.ExecContext(ctx, `
insert into user_todo_projections(tenant,todo_id,user_id,title,description,status,priority,due_date,tags,completed_at,archived_at,source_event_id,metadata,created_at,updated_at,deleted_at)
values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,now(),now(),case when $6='DELETED' then now() else null end)
on conflict(tenant,todo_id) do update set user_id=excluded.user_id,title=excluded.title,description=excluded.description,status=excluded.status,priority=excluded.priority,due_date=excluded.due_date,tags=excluded.tags,completed_at=excluded.completed_at,archived_at=excluded.archived_at,source_event_id=excluded.source_event_id,metadata=excluded.metadata,updated_at=now(),deleted_at=excluded.deleted_at`,
		e.Tenant, id, e.UserID, valueString(jsonValueMap(e.Payload, "title"), ""), stringValue(e.Payload, "description"), status, priority, nullTimePtr(timeValue(e.Payload, "due_date")), rawValue(e.Payload, "tags", domain.EmptyArray()), nullTimePtr(timeValue(e.Payload, "completed_at")), nullTimePtr(timeValue(e.Payload, "archived_at")), e.EventID, e.Payload)
	if err != nil {
		return err
	}
	return r.insertActivityTx(ctx, tx, eventActivity(e, "todo projection updated"))
}

func (r *PostgresRepository) applyReportProjectionTx(ctx context.Context, tx *sql.Tx, e domain.EventEnvelope) error {
	id := e.AggregateID
	if id == "" {
		id = stringValue(e.Payload, "report_id")
	}
	if id == "" {
		return nil
	}
	status := stringValue(e.Payload, "status")
	if status == "" {
		status = strings.ToUpper(strings.TrimPrefix(e.EventType, "report."))
	}
	requester := stringValue(e.Payload, "requester_user_id")
	if requester == "" {
		requester = e.ActorID
	}
	target := stringValue(e.Payload, "target_user_id")
	if target == "" {
		target = e.UserID
	}
	_, err := tx.ExecContext(ctx, `
insert into user_report_projections(tenant,report_id,requester_user_id,target_user_id,report_type,format,status,file_name,s3_object_key,download_url,error_message,expires_at,metadata,source_event_id,created_at,updated_at)
values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,now(),now())
on conflict(tenant,report_id) do update set requester_user_id=excluded.requester_user_id,target_user_id=excluded.target_user_id,report_type=excluded.report_type,format=excluded.format,status=excluded.status,file_name=excluded.file_name,s3_object_key=excluded.s3_object_key,download_url=excluded.download_url,error_message=excluded.error_message,expires_at=excluded.expires_at,metadata=excluded.metadata,source_event_id=excluded.source_event_id,updated_at=now(),deleted_at=null`,
		e.Tenant, id, requester, target, stringValue(e.Payload, "report_type"), stringValue(e.Payload, "format"), status, stringValue(e.Payload, "file_name"), stringValue(e.Payload, "s3_object_key"), stringValue(e.Payload, "download_url"), stringValue(e.Payload, "error_message"), nullTimePtr(timeValue(e.Payload, "expires_at")), e.Payload, e.EventID)
	if err != nil {
		return err
	}
	_, _ = tx.ExecContext(ctx, `update user_report_requests set status=$3,file_name=$4,s3_object_key=$5,download_url=$6,error_message=$7,expires_at=$8,updated_at=now() where tenant=$1 and report_id=$2`, e.Tenant, id, status, stringValue(e.Payload, "file_name"), stringValue(e.Payload, "s3_object_key"), stringValue(e.Payload, "download_url"), stringValue(e.Payload, "error_message"), nullTimePtr(timeValue(e.Payload, "expires_at")))
	return r.insertActivityTx(ctx, tx, eventActivity(e, "report projection updated"))
}

func (r *PostgresRepository) applyAccessProjectionTx(ctx context.Context, tx *sql.Tx, e domain.EventEnvelope) error {
	requestID := stringValue(e.Payload, "request_id")
	if requestID == "" && e.AggregateType == "access_request" {
		requestID = e.AggregateID
	}
	status := stringValue(e.Payload, "status")
	if status == "" {
		switch {
		case strings.Contains(e.EventType, "approved"):
			status = domain.StatusApproved
		case strings.Contains(e.EventType, "rejected"):
			status = domain.StatusRejected
		case strings.Contains(e.EventType, "revoked"):
			status = domain.StatusRevoked
		default:
			status = domain.StatusPending
		}
	}
	if requestID != "" {
		_, _ = tx.ExecContext(ctx, `update user_access_requests set status=$3,decision_reason=$4,decided_by=$5,decided_at=now(),updated_at=now() where tenant=$1 and request_id=$2`, e.Tenant, requestID, status, stringValue(e.Payload, "reason"), e.ActorID)
	}
	grantID := stringValue(e.Payload, "grant_id")
	if grantID == "" && e.AggregateType == "access_grant" {
		grantID = e.AggregateID
	}
	if grantID != "" && status != domain.StatusRejected {
		expires := timeValue(e.Payload, "expires_at")
		if expires == nil {
			future := time.Now().UTC().Add(30 * 24 * time.Hour)
			expires = &future
		}
		requester := stringValue(e.Payload, "requester_user_id")
		if requester == "" {
			requester = stringValue(e.Payload, "actor_user_id")
		}
		target := stringValue(e.Payload, "target_user_id")
		_, err := tx.ExecContext(ctx, `
insert into user_access_grants(tenant,grant_id,request_id,requester_user_id,target_user_id,resource_type,scope,status,approved_by,revoked_by,reason,expires_at,revoked_at,metadata,created_at,updated_at,deleted_at)
values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,case when $8='REVOKED' then now() else null end,$13,now(),now(),case when $8='REVOKED' then now() else null end)
on conflict(tenant,grant_id) do update set request_id=excluded.request_id,requester_user_id=excluded.requester_user_id,target_user_id=excluded.target_user_id,resource_type=excluded.resource_type,scope=excluded.scope,status=excluded.status,approved_by=excluded.approved_by,revoked_by=excluded.revoked_by,reason=excluded.reason,expires_at=excluded.expires_at,revoked_at=excluded.revoked_at,metadata=excluded.metadata,updated_at=now(),deleted_at=excluded.deleted_at`,
			e.Tenant, grantID, requestID, requester, target, stringValue(e.Payload, "resource_type"), stringValue(e.Payload, "scope"), mapAccessGrantStatus(status), stringValue(e.Payload, "approved_by"), stringValue(e.Payload, "revoked_by"), stringValue(e.Payload, "reason"), *expires, e.Payload)
		if err != nil {
			return err
		}
	}
	return r.insertActivityTx(ctx, tx, eventActivity(e, "access projection updated"))
}

func (r *PostgresRepository) applyUserProjectionTx(ctx context.Context, tx *sql.Tx, e domain.EventEnvelope) error {
	if e.UserID == "" {
		return nil
	}
	username := stringValue(e.Payload, "username")
	email := stringValue(e.Payload, "email")
	role := stringValue(e.Payload, "role")
	if role == "" {
		role = "user"
	}
	adminStatus := stringValue(e.Payload, "admin_status")
	if adminStatus == "" {
		adminStatus = "not_requested"
	}
	status := stringValue(e.Payload, "status")
	if status == "" {
		status = "active"
	}
	_, err := tx.ExecContext(ctx, `
insert into user_profiles(tenant,user_id,username,email,role,admin_status,status,timezone,locale,metadata,created_at,updated_at)
values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,now(),now())
on conflict(tenant,user_id) do update set username=coalesce(nullif(excluded.username,''),user_profiles.username),email=coalesce(nullif(excluded.email,''),user_profiles.email),role=excluded.role,admin_status=excluded.admin_status,status=excluded.status,metadata=excluded.metadata,updated_at=now(),deleted_at=null`, e.Tenant, e.UserID, username, email, role, adminStatus, status, r.cfg.DefaultTimezone, r.cfg.DefaultLocale, e.Payload)
	if err != nil {
		return err
	}
	_, _ = tx.ExecContext(ctx, `insert into user_preferences(tenant,user_id,timezone,locale,theme,notifications_enabled,metadata,created_at,updated_at) values($1,$2,$3,$4,$5,true,'{}',now(),now()) on conflict(tenant,user_id) do nothing`, e.Tenant, e.UserID, r.cfg.DefaultTimezone, r.cfg.DefaultLocale, r.cfg.DefaultTheme)
	return nil
}

func jsonValueMap(payload []byte, key string) any { return jsonValue(payload, key) }

func mapAccessGrantStatus(status string) string {
	status = strings.ToUpper(status)
	if status == domain.StatusApproved {
		return domain.StatusActive
	}
	return status
}

func projectionSummary(eventType, id string) string { return fmt.Sprintf("%s %s", eventType, id) }
