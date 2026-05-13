package persistence

import (
	"context"
	"database/sql"
	"encoding/json"
	"strings"
	"time"

	"user_service/internal/domain"
	"user_service/internal/rbac"
)

func (r *PostgresRepository) CreateAccessRequest(ctx context.Context, request domain.AccessRequest, event domain.EventEnvelope) (domain.AccessRequest, error) {
	tx, err := r.db.BeginTx(ctx, &sql.TxOptions{})
	if err != nil {
		return domain.AccessRequest{}, err
	}
	defer tx.Rollback()
	if len(request.Metadata) == 0 {
		request.Metadata = domain.EmptyObject()
	}
	_, err = tx.ExecContext(ctx, `
insert into user_access_requests(tenant,request_id,requester_user_id,target_user_id,resource_type,scope,reason,status,expires_at,metadata,created_at,updated_at)
values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,now(),now())`, request.Tenant, request.RequestID, request.RequesterUserID, request.TargetUserID, request.ResourceType, request.Scope, request.Reason, request.Status, request.ExpiresAt, request.Metadata)
	if err != nil {
		return domain.AccessRequest{}, err
	}
	if err := r.insertOutboxTx(ctx, tx, event, "access.events"); err != nil {
		return domain.AccessRequest{}, err
	}
	_ = r.insertActivityTx(ctx, tx, eventActivity(event, "access request created"))
	if err := tx.Commit(); err != nil {
		return domain.AccessRequest{}, err
	}
	return r.GetAccessRequest(ctx, request.Tenant, request.RequesterUserID, request.RequestID)
}

func (r *PostgresRepository) ListAccessRequests(ctx context.Context, tenant, requesterID string, page Page) ([]domain.AccessRequest, error) {
	rows, err := r.db.QueryContext(ctx, `
select tenant,request_id,requester_user_id,target_user_id,resource_type,scope,reason,status,expires_at,coalesce(decision_reason,''),coalesce(decided_by,''),decided_at,cancelled_at,metadata,created_at,updated_at
from user_access_requests where tenant=$1 and requester_user_id=$2 and deleted_at is null order by created_at desc limit $3 offset $4`, tenant, requesterID, page.Limit, page.Offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.AccessRequest{}
	for rows.Next() {
		ar, err := scanAccessRequest(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, ar)
	}
	return out, rows.Err()
}

func (r *PostgresRepository) GetAccessRequest(ctx context.Context, tenant, requesterID, requestID string) (domain.AccessRequest, error) {
	row := r.db.QueryRowContext(ctx, `
select tenant,request_id,requester_user_id,target_user_id,resource_type,scope,reason,status,expires_at,coalesce(decision_reason,''),coalesce(decided_by,''),decided_at,cancelled_at,metadata,created_at,updated_at
from user_access_requests where tenant=$1 and requester_user_id=$2 and request_id=$3 and deleted_at is null`, tenant, requesterID, requestID)
	return scanAccessRequest(row)
}

func (r *PostgresRepository) GetAccessRequestByID(ctx context.Context, tenant, requestID string) (domain.AccessRequest, error) {
	row := r.db.QueryRowContext(ctx, `
select tenant,request_id,requester_user_id,target_user_id,resource_type,scope,reason,status,expires_at,coalesce(decision_reason,''),coalesce(decided_by,''),decided_at,cancelled_at,metadata,created_at,updated_at
from user_access_requests where tenant=$1 and request_id=$2 and deleted_at is null`, tenant, requestID)
	return scanAccessRequest(row)
}

func scanAccessRequest(row interface{ Scan(dest ...any) error }) (domain.AccessRequest, error) {
	var ar domain.AccessRequest
	var decided, cancelled sql.NullTime
	var metadata []byte
	if err := row.Scan(&ar.Tenant, &ar.RequestID, &ar.RequesterUserID, &ar.TargetUserID, &ar.ResourceType, &ar.Scope, &ar.Reason, &ar.Status, &ar.ExpiresAt, &ar.DecisionReason, &ar.DecidedBy, &decided, &cancelled, &metadata, &ar.CreatedAt, &ar.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return domain.AccessRequest{}, ErrNotFound
		}
		return domain.AccessRequest{}, err
	}
	if decided.Valid {
		ar.DecidedAt = &decided.Time
	}
	if cancelled.Valid {
		ar.CancelledAt = &cancelled.Time
	}
	ar.Metadata = emptyJSON(metadata, "{}")
	return ar, nil
}

func (r *PostgresRepository) CancelAccessRequest(ctx context.Context, tenant, requesterID, requestID string, event domain.EventEnvelope) (domain.AccessRequest, error) {
	current, err := r.GetAccessRequest(ctx, tenant, requesterID, requestID)
	if err != nil {
		return domain.AccessRequest{}, err
	}
	return r.cancelAccessRequest(ctx, tenant, requestID, current.RequesterUserID, event)
}

func (r *PostgresRepository) CancelAccessRequestByID(ctx context.Context, tenant, requestID string, event domain.EventEnvelope) (domain.AccessRequest, error) {
	current, err := r.GetAccessRequestByID(ctx, tenant, requestID)
	if err != nil {
		return domain.AccessRequest{}, err
	}
	return r.cancelAccessRequest(ctx, tenant, requestID, current.RequesterUserID, event)
}

func (r *PostgresRepository) cancelAccessRequest(ctx context.Context, tenant, requestID, requesterID string, event domain.EventEnvelope) (domain.AccessRequest, error) {
	tx, err := r.db.BeginTx(ctx, &sql.TxOptions{})
	if err != nil {
		return domain.AccessRequest{}, err
	}
	defer tx.Rollback()
	var currentStatus string
	if err := tx.QueryRowContext(ctx, `select status from user_access_requests where tenant=$1 and request_id=$2 and deleted_at is null for update`, tenant, requestID).Scan(&currentStatus); err != nil {
		if err == sql.ErrNoRows {
			return domain.AccessRequest{}, ErrNotFound
		}
		return domain.AccessRequest{}, err
	}
	if currentStatus != domain.StatusPending {
		return domain.AccessRequest{}, ErrNotFound
	}
	_, err = tx.ExecContext(ctx, `update user_access_requests set status=$3,cancelled_at=now(),updated_at=now() where tenant=$1 and request_id=$2`, tenant, requestID, domain.StatusCancelled)
	if err != nil {
		return domain.AccessRequest{}, err
	}
	if err := r.insertOutboxTx(ctx, tx, event, "access.events"); err != nil {
		return domain.AccessRequest{}, err
	}
	_ = r.insertActivityTx(ctx, tx, eventActivity(event, "access request cancelled"))
	if err := tx.Commit(); err != nil {
		return domain.AccessRequest{}, err
	}
	return r.GetAccessRequest(ctx, tenant, requesterID, requestID)
}

func (r *PostgresRepository) ListVisibleGrants(ctx context.Context, tenant string, claims domain.Claims, page Page) ([]domain.AccessGrant, error) {
	var rows *sql.Rows
	var err error
	if claims.IsApprovedAdmin() || claims.IsService() {
		rows, err = r.db.QueryContext(ctx, grantSelect()+` where tenant=$1 and deleted_at is null order by created_at desc limit $2 offset $3`, tenant, page.Limit, page.Offset)
	} else {
		rows, err = r.db.QueryContext(ctx, grantSelect()+` where tenant=$1 and (requester_user_id=$2 or target_user_id=$2) and deleted_at is null order by created_at desc limit $3 offset $4`, tenant, claims.Subject, page.Limit, page.Offset)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.AccessGrant{}
	for rows.Next() {
		g, err := scanAccessGrant(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, rows.Err()
}

func grantSelect() string {
	return `select tenant,grant_id,coalesce(request_id,''),requester_user_id,target_user_id,resource_type,scope,status,coalesce(approved_by,''),coalesce(revoked_by,''),coalesce(reason,''),expires_at,revoked_at,metadata,created_at,updated_at from user_access_grants`
}

func scanAccessGrant(row interface{ Scan(dest ...any) error }) (domain.AccessGrant, error) {
	var g domain.AccessGrant
	var revoked sql.NullTime
	var metadata []byte
	if err := row.Scan(&g.Tenant, &g.GrantID, &g.RequestID, &g.RequesterUserID, &g.TargetUserID, &g.ResourceType, &g.Scope, &g.Status, &g.ApprovedBy, &g.RevokedBy, &g.Reason, &g.ExpiresAt, &revoked, &metadata, &g.CreatedAt, &g.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return domain.AccessGrant{}, ErrNotFound
		}
		return domain.AccessGrant{}, err
	}
	if revoked.Valid {
		g.RevokedAt = &revoked.Time
	}
	g.Metadata = emptyJSON(metadata, "{}")
	return g, nil
}

func (r *PostgresRepository) HasActiveGrant(ctx context.Context, tenant, actorUserID, targetUserID, resourceType, requiredScope string, at time.Time) (bool, error) {
	rows, err := r.db.QueryContext(ctx, `select scope from user_access_grants where tenant=$1 and requester_user_id=$2 and target_user_id=$3 and resource_type=$4 and status=$5 and expires_at > $6 and deleted_at is null`, tenant, actorUserID, targetUserID, resourceType, domain.StatusActive, at)
	if err != nil {
		return false, err
	}
	defer rows.Close()
	for rows.Next() {
		var scope string
		if err := rows.Scan(&scope); err != nil {
			return false, err
		}
		if rbac.ScopeMatches(scope, requiredScope, false) {
			return true, nil
		}
	}
	return false, rows.Err()
}

func (r *PostgresRepository) CreateReportRequest(ctx context.Context, report domain.ReportRequest, event domain.EventEnvelope) (domain.ReportRequest, error) {
	tx, err := r.db.BeginTx(ctx, &sql.TxOptions{})
	if err != nil {
		return domain.ReportRequest{}, err
	}
	defer tx.Rollback()
	report.Filters = emptyJSON(report.Filters, "{}")
	report.Options = emptyJSON(report.Options, "{}")
	_, err = tx.ExecContext(ctx, `
insert into user_report_requests(tenant,report_id,requester_user_id,target_user_id,report_type,format,date_from,date_to,filters,options,status,created_at,updated_at)
values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,now(),now())`, report.Tenant, report.ReportID, report.RequesterUserID, report.TargetUserID, report.ReportType, report.Format, nullTimePtr(report.DateFrom), nullTimePtr(report.DateTo), report.Filters, report.Options, report.Status)
	if err != nil {
		return domain.ReportRequest{}, err
	}
	if err := r.insertOutboxTx(ctx, tx, event, r.cfg.KafkaEventsTopic); err != nil {
		return domain.ReportRequest{}, err
	}
	_ = r.insertActivityTx(ctx, tx, eventActivity(event, "report request created"))
	if err := tx.Commit(); err != nil {
		return domain.ReportRequest{}, err
	}
	return r.GetReportRequest(ctx, report.Tenant, report.RequesterUserID, report.TargetUserID, report.ReportID)
}

func (r *PostgresRepository) ListReportRequests(ctx context.Context, tenant, requesterID, targetUserID string, page Page) ([]domain.ReportRequest, error) {
	var rows *sql.Rows
	var err error
	if requesterID == "" {
		rows, err = r.db.QueryContext(ctx, reportSelect()+` where tenant=$1 and target_user_id=$2 and deleted_at is null order by created_at desc limit $3 offset $4`, tenant, targetUserID, page.Limit, page.Offset)
	} else {
		rows, err = r.db.QueryContext(ctx, reportSelect()+` where tenant=$1 and requester_user_id=$2 and target_user_id=$3 and deleted_at is null order by created_at desc limit $4 offset $5`, tenant, requesterID, targetUserID, page.Limit, page.Offset)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.ReportRequest{}
	for rows.Next() {
		rr, err := scanReportRequest(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, rr)
	}
	return out, rows.Err()
}

func (r *PostgresRepository) GetReportRequest(ctx context.Context, tenant, requesterID, targetUserID, reportID string) (domain.ReportRequest, error) {
	if requesterID == "" {
		return scanReportRequest(r.db.QueryRowContext(ctx, reportSelect()+` where tenant=$1 and target_user_id=$2 and report_id=$3 and deleted_at is null`, tenant, targetUserID, reportID))
	}
	row := r.db.QueryRowContext(ctx, reportSelect()+` where tenant=$1 and requester_user_id=$2 and target_user_id=$3 and report_id=$4 and deleted_at is null`, tenant, requesterID, targetUserID, reportID)
	return scanReportRequest(row)
}

func reportSelect() string {
	return `select tenant,report_id,requester_user_id,target_user_id,report_type,format,date_from,date_to,filters,options,status,coalesce(file_name,''),coalesce(s3_object_key,''),coalesce(download_url,''),coalesce(error_message,''),expires_at,created_at,updated_at from user_report_requests`
}

func scanReportRequest(row interface{ Scan(dest ...any) error }) (domain.ReportRequest, error) {
	var rr domain.ReportRequest
	var from, to, expires sql.NullTime
	var filters, options []byte
	if err := row.Scan(&rr.Tenant, &rr.ReportID, &rr.RequesterUserID, &rr.TargetUserID, &rr.ReportType, &rr.Format, &from, &to, &filters, &options, &rr.Status, &rr.FileName, &rr.S3ObjectKey, &rr.DownloadURL, &rr.ErrorMessage, &expires, &rr.CreatedAt, &rr.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return domain.ReportRequest{}, ErrNotFound
		}
		return domain.ReportRequest{}, err
	}
	if from.Valid {
		rr.DateFrom = &from.Time
	}
	if to.Valid {
		rr.DateTo = &to.Time
	}
	if expires.Valid {
		rr.ExpiresAt = &expires.Time
	}
	rr.Filters = emptyJSON(filters, "{}")
	rr.Options = emptyJSON(options, "{}")
	return rr, nil
}

func (r *PostgresRepository) CancelReportRequest(ctx context.Context, tenant, requesterID, targetUserID, reportID string, event domain.EventEnvelope) (domain.ReportRequest, error) {
	tx, err := r.db.BeginTx(ctx, &sql.TxOptions{})
	if err != nil {
		return domain.ReportRequest{}, err
	}
	defer tx.Rollback()
	var currentStatus string
	var lockErr error
	if requesterID == "" {
		lockErr = tx.QueryRowContext(ctx, `select status from user_report_requests where tenant=$1 and target_user_id=$2 and report_id=$3 and deleted_at is null for update`, tenant, targetUserID, reportID).Scan(&currentStatus)
	} else {
		lockErr = tx.QueryRowContext(ctx, `select status from user_report_requests where tenant=$1 and requester_user_id=$2 and target_user_id=$3 and report_id=$4 and deleted_at is null for update`, tenant, requesterID, targetUserID, reportID).Scan(&currentStatus)
	}
	if lockErr != nil {
		if lockErr == sql.ErrNoRows {
			return domain.ReportRequest{}, ErrNotFound
		}
		return domain.ReportRequest{}, lockErr
	}
	if strings.EqualFold(currentStatus, "COMPLETED") || strings.EqualFold(currentStatus, "FAILED") || strings.EqualFold(currentStatus, domain.StatusCancelled) {
		return domain.ReportRequest{}, sql.ErrNoRows
	}
	if requesterID == "" {
		_, err = tx.ExecContext(ctx, `update user_report_requests set status=$4,updated_at=now() where tenant=$1 and target_user_id=$2 and report_id=$3`, tenant, targetUserID, reportID, domain.StatusCancelled)
	} else {
		_, err = tx.ExecContext(ctx, `update user_report_requests set status=$5,updated_at=now() where tenant=$1 and requester_user_id=$2 and target_user_id=$3 and report_id=$4`, tenant, requesterID, targetUserID, reportID, domain.StatusCancelled)
	}
	if err != nil {
		return domain.ReportRequest{}, err
	}
	if err := r.insertOutboxTx(ctx, tx, event, r.cfg.KafkaEventsTopic); err != nil {
		return domain.ReportRequest{}, err
	}
	_ = r.insertActivityTx(ctx, tx, eventActivity(event, "report request cancelled"))
	if err := tx.Commit(); err != nil {
		return domain.ReportRequest{}, err
	}
	return r.GetReportRequest(ctx, tenant, requesterID, targetUserID, reportID)
}

func marshalRaw(v any) json.RawMessage { return domain.RawJSON(v) }
