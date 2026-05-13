package persistence

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"user_service/internal/config"
	"user_service/internal/domain"
	"user_service/internal/observability"
	"user_service/internal/platform"

	_ "github.com/jackc/pgx/v5/stdlib"
)

var ErrNotFound = errors.New("record not found")

type PostgresRepository struct {
	cfg config.Config
	db  *sql.DB
}

func NewPostgres(ctx context.Context, cfg config.Config) (*PostgresRepository, error) {
	db, err := sql.Open("pgx", cfg.PostgresDSN())
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(cfg.PostgresPoolSize + cfg.PostgresMaxOverflow)
	db.SetMaxIdleConns(cfg.PostgresPoolSize)
	db.SetConnMaxLifetime(30 * time.Minute)
	repo := &PostgresRepository{cfg: cfg, db: db}
	if err := repo.Ping(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	return repo, nil
}

func (r *PostgresRepository) Close() error {
	if r == nil || r.db == nil {
		return nil
	}
	return r.db.Close()
}

func (r *PostgresRepository) Ping(ctx context.Context) error {
	if r == nil || r.db == nil {
		return errors.New("postgres repository not initialized")
	}
	return observability.CaptureDependency(ctx, "PostgreSQL ping", observability.SpanTypePostgres, func(spanCtx context.Context) error {
		return r.db.PingContext(spanCtx)
	})
}

func (r *PostgresRepository) Migrate(ctx context.Context, migrationsDir string) error {
	if strings.ToLower(r.cfg.PostgresMigrationMode) == "none" {
		return nil
	}
	entries, err := os.ReadDir(migrationsDir)
	if err != nil {
		return err
	}
	files := make([]string, 0)
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".up.sql") {
			continue
		}
		files = append(files, filepath.Join(migrationsDir, entry.Name()))
	}
	sort.Strings(files)
	if len(files) == 0 {
		return fmt.Errorf("no migration files found in %s", migrationsDir)
	}
	for _, file := range files {
		body, err := os.ReadFile(file)
		if err != nil {
			return err
		}
		if err := observability.CaptureDependency(ctx, "PostgreSQL migration", observability.SpanTypePostgres, func(spanCtx context.Context) error {
			_, execErr := r.db.ExecContext(spanCtx, string(body))
			return execErr
		}); err != nil {
			return fmt.Errorf("migration %s failed: %w", filepath.Base(file), err)
		}
	}
	return nil
}

func (r *PostgresRepository) PendingOutboxCount(ctx context.Context) (int, error) {
	var count int
	err := observability.CaptureDependency(ctx, "PostgreSQL outbox count", observability.SpanTypePostgres, func(spanCtx context.Context) error {
		return r.db.QueryRowContext(spanCtx, `select count(*) from outbox_events where status in ('PENDING','FAILED')`).Scan(&count)
	})
	return count, err
}

func (r *PostgresRepository) insertOutboxTx(ctx context.Context, tx *sql.Tx, event domain.EventEnvelope, topic string) error {
	payload, err := json.Marshal(event)
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `
insert into outbox_events(event_id, tenant, aggregate_type, aggregate_id, event_type, event_version, topic, payload, status, request_id, trace_id, correlation_id, created_at, updated_at)
values($1,$2,$3,$4,$5,$6,$7,$8,'PENDING',$9,$10,$11,now(),now())
on conflict(event_id) do nothing`, event.EventID, event.Tenant, event.AggregateType, event.AggregateID, event.EventType, event.EventVersion, topic, payload, event.RequestID, event.TraceID, event.CorrelationID)
	return err
}

func (r *PostgresRepository) insertActivityTx(ctx context.Context, tx *sql.Tx, a domain.ActivityEvent) error {
	if len(a.Metadata) == 0 {
		a.Metadata = domain.EmptyObject()
	}
	if len(a.Payload) == 0 {
		a.Payload = domain.EmptyObject()
	}
	_, err := tx.ExecContext(ctx, `
insert into user_activity_events(id, event_id, tenant, user_id, actor_id, target_user_id, event_type, resource_type, resource_id, source_service, aggregate_type, aggregate_id, summary, payload, request_id, trace_id, correlation_id, metadata, created_at, updated_at)
values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$19)
on conflict(id) do nothing`, a.ID, a.EventID, a.Tenant, a.UserID, a.ActorID, a.TargetUserID, a.EventType, a.ResourceType, a.ResourceID, a.SourceService, a.AggregateType, a.AggregateID, a.Summary, a.Payload, a.RequestID, a.TraceID, a.CorrelationID, a.Metadata, a.CreatedAt)
	return err
}

func (r *PostgresRepository) LockOutboxBatch(ctx context.Context, limit int) ([]domain.OutboxEvent, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	tx, err := r.db.BeginTx(ctx, &sql.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	rows, err := tx.QueryContext(ctx, `
select id::text, event_id, tenant, aggregate_type, aggregate_id, event_type, topic, payload, attempt_count
from outbox_events
where status in ('PENDING','FAILED') and (next_retry_at is null or next_retry_at <= now())
order by created_at
limit $1
for update skip locked`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]domain.OutboxEvent, 0)
	ids := make([]string, 0)
	for rows.Next() {
		var e domain.OutboxEvent
		if err := rows.Scan(&e.ID, &e.EventID, &e.Tenant, &e.AggregateType, &e.AggregateID, &e.EventType, &e.Topic, &e.Payload, &e.AttemptCount); err != nil {
			return nil, err
		}
		out = append(out, e)
		ids = append(ids, e.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for _, id := range ids {
		if _, err := tx.ExecContext(ctx, `update outbox_events set status='PROCESSING', updated_at=now() where id=$1::uuid`, id); err != nil {
			return nil, err
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return out, nil
}

func (r *PostgresRepository) MarkOutboxSent(ctx context.Context, id string) error {
	_, err := r.db.ExecContext(ctx, `update outbox_events set status='SENT', sent_at=now(), updated_at=now() where id=$1::uuid`, id)
	return err
}

func (r *PostgresRepository) MarkOutboxFailed(ctx context.Context, id, message string, maxAttempts int) error {
	if maxAttempts <= 0 {
		maxAttempts = 10
	}
	_, err := r.db.ExecContext(ctx, `
update outbox_events
set attempt_count=attempt_count+1,
    last_error=$2,
    status=case when attempt_count + 1 >= $3 then 'DEAD_LETTERED' else 'FAILED' end,
    next_retry_at=case when attempt_count + 1 >= $3 then null else now() + interval '30 seconds' end,
    updated_at=now()
where id=$1::uuid`, id, truncate(message, 2000), maxAttempts)
	return err
}

func (r *PostgresRepository) ProcessInboundEvent(ctx context.Context, topic string, partition int, offset int64, envelope domain.EventEnvelope) error {
	tx, err := r.db.BeginTx(ctx, &sql.TxOptions{})
	if err != nil {
		return err
	}
	defer tx.Rollback()
	payload, _ := json.Marshal(envelope)
	result, err := tx.ExecContext(ctx, `
insert into kafka_inbox_events(event_id, tenant, topic, partition, offset_value, event_type, source_service, payload, status, created_at)
values($1,$2,$3,$4,$5,$6,$7,$8,'RECEIVED',now())
on conflict(event_id) do nothing`, envelope.EventID, envelope.Tenant, topic, partition, offset, envelope.EventType, envelope.Service, payload)
	if err != nil {
		return err
	}
	affected, _ := result.RowsAffected()
	if affected == 0 {
		return tx.Commit()
	}
	if _, err := tx.ExecContext(ctx, `update kafka_inbox_events set status='PROCESSING' where event_id=$1`, envelope.EventID); err != nil {
		return err
	}
	if err := r.applyProjectionTx(ctx, tx, envelope); err != nil {
		_, _ = tx.ExecContext(ctx, `update kafka_inbox_events set status='FAILED', error_message=$2 where event_id=$1`, envelope.EventID, truncate(err.Error(), 2000))
		return err
	}
	_, err = tx.ExecContext(ctx, `update kafka_inbox_events set status='PROCESSED', processed_at=now() where event_id=$1`, envelope.EventID)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func (r *PostgresRepository) applyProjectionTx(ctx context.Context, tx *sql.Tx, e domain.EventEnvelope) error {
	switch {
	case strings.HasPrefix(e.EventType, "calculation."):
		return r.applyCalculationProjectionTx(ctx, tx, e)
	case strings.HasPrefix(e.EventType, "todo."):
		return r.applyTodoProjectionTx(ctx, tx, e)
	case strings.HasPrefix(e.EventType, "report."):
		return r.applyReportProjectionTx(ctx, tx, e)
	case strings.HasPrefix(e.EventType, "access.") || strings.Contains(e.EventType, ".access."):
		return r.applyAccessProjectionTx(ctx, tx, e)
	case strings.HasPrefix(e.EventType, "auth.") || strings.HasPrefix(e.EventType, "user."):
		return r.applyUserProjectionTx(ctx, tx, e)
	default:
		return nil
	}
}

func eventActivity(e domain.EventEnvelope, summary string) domain.ActivityEvent {
	return domain.ActivityEvent{ID: platform.NewID("act"), EventID: e.EventID, Tenant: e.Tenant, UserID: e.UserID, ActorID: e.ActorID, TargetUserID: stringValue(e.Payload, "target_user_id"), EventType: e.EventType, ResourceType: e.AggregateType, ResourceID: e.AggregateID, SourceService: e.Service, AggregateType: e.AggregateType, AggregateID: e.AggregateID, Summary: summary, Payload: e.Payload, RequestID: e.RequestID, TraceID: e.TraceID, CorrelationID: e.CorrelationID, Metadata: e.Payload, CreatedAt: time.Now().UTC()}
}

func jsonValue(payload json.RawMessage, key string) any {
	var m map[string]any
	if err := json.Unmarshal(payload, &m); err != nil {
		return nil
	}
	return m[key]
}

func stringValue(payload json.RawMessage, key string) string {
	v := jsonValue(payload, key)
	if v == nil {
		return ""
	}
	return fmt.Sprint(v)
}

func rawValue(payload json.RawMessage, key string, fallback json.RawMessage) json.RawMessage {
	var m map[string]json.RawMessage
	if err := json.Unmarshal(payload, &m); err != nil {
		return fallback
	}
	if v, ok := m[key]; ok && len(v) > 0 && string(v) != "null" {
		return v
	}
	return fallback
}

func timeValue(payload json.RawMessage, key string) *time.Time {
	v := stringValue(payload, key)
	if v == "" {
		return nil
	}
	if t, err := time.Parse(time.RFC3339, v); err == nil {
		utc := t.UTC()
		return &utc
	}
	if t, err := time.Parse("2006-01-02", v); err == nil {
		utc := t.UTC()
		return &utc
	}
	return nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

func nullTimePtr(t *time.Time) any {
	if t == nil || t.IsZero() {
		return nil
	}
	return *t
}

func emptyJSON(v json.RawMessage, fallback string) json.RawMessage {
	if len(v) == 0 || !json.Valid(v) {
		return json.RawMessage(fallback)
	}
	return v
}
