package persistence

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"user_service/internal/domain"
	"user_service/internal/platform"
)

func (r *PostgresRepository) EnsureProfile(ctx context.Context, claims domain.Claims, defaults ProfileDefaults) (domain.UserProfile, error) {
	now := time.Now().UTC()
	status := claims.Status
	if status == "" {
		status = "active"
	}
	_, err := r.db.ExecContext(ctx, `
insert into user_profiles(tenant, user_id, username, email, role, admin_status, status, timezone, locale, metadata, created_at, updated_at)
values($1,$2,$3,$4,$5,$6,$7,$8,$9,'{}',now(),now())
on conflict(tenant, user_id) do update set
  username=excluded.username,
  email=excluded.email,
  role=excluded.role,
  admin_status=excluded.admin_status,
  status=excluded.status,
  updated_at=now()`, claims.Tenant, claims.Subject, claims.Username, claims.Email, claims.Role, claims.AdminStatus, status, defaults.Timezone, defaults.Locale)
	if err != nil {
		return domain.UserProfile{}, err
	}
	_, _ = r.db.ExecContext(ctx, `
insert into user_preferences(tenant, user_id, timezone, locale, theme, notifications_enabled, metadata, created_at, updated_at)
values($1,$2,$3,$4,$5,true,'{}',$6,$6)
on conflict(tenant, user_id) do nothing`, claims.Tenant, claims.Subject, defaults.Timezone, defaults.Locale, defaults.Theme, now)
	return r.GetProfile(ctx, claims.Tenant, claims.Subject)
}

func (r *PostgresRepository) GetProfile(ctx context.Context, tenant, userID string) (domain.UserProfile, error) {
	row := r.db.QueryRowContext(ctx, `
select id,tenant,user_id,username,email,coalesce(full_name,''),coalesce(display_name,''),coalesce(bio,''),birthdate,coalesce(gender,''),role,admin_status,status,timezone,locale,coalesce(avatar_url,''),coalesce(phone,''),coalesce(source_event_id,''),last_seen_at,metadata,created_at,updated_at
from user_profiles where tenant=$1 and user_id=$2 and deleted_at is null`, tenant, userID)
	return scanProfile(row)
}

func scanProfile(row interface{ Scan(dest ...any) error }) (domain.UserProfile, error) {
	var p domain.UserProfile
	var birth, lastSeen sql.NullTime
	var metadata []byte
	if err := row.Scan(&p.ID, &p.Tenant, &p.UserID, &p.Username, &p.Email, &p.FullName, &p.DisplayName, &p.Bio, &birth, &p.Gender, &p.Role, &p.AdminStatus, &p.Status, &p.Timezone, &p.Locale, &p.AvatarURL, &p.Phone, &p.SourceEventID, &lastSeen, &metadata, &p.CreatedAt, &p.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return domain.UserProfile{}, ErrNotFound
		}
		return domain.UserProfile{}, err
	}
	if birth.Valid {
		p.Birthdate = &birth.Time
	}
	if lastSeen.Valid {
		p.LastSeenAt = &lastSeen.Time
	}
	p.Metadata = emptyJSON(metadata, "{}")
	return p, nil
}

func (r *PostgresRepository) UpdateProfile(ctx context.Context, tenant, userID string, patch map[string]any, event domain.EventEnvelope) (domain.UserProfile, error) {
	tx, err := r.db.BeginTx(ctx, &sql.TxOptions{})
	if err != nil {
		return domain.UserProfile{}, err
	}
	defer tx.Rollback()
	current, err := scanProfile(tx.QueryRowContext(ctx, `
select id,tenant,user_id,username,email,coalesce(full_name,''),coalesce(display_name,''),coalesce(bio,''),birthdate,coalesce(gender,''),role,admin_status,status,timezone,locale,coalesce(avatar_url,''),coalesce(phone,''),coalesce(source_event_id,''),last_seen_at,metadata,created_at,updated_at
from user_profiles where tenant=$1 and user_id=$2 and deleted_at is null for update`, tenant, userID))
	if err != nil {
		return domain.UserProfile{}, err
	}
	fullName := stringPatch(patch, "full_name", current.FullName)
	displayName := stringPatch(patch, "display_name", current.DisplayName)
	bio := stringPatch(patch, "bio", current.Bio)
	gender := stringPatch(patch, "gender", current.Gender)
	timezone := stringPatch(patch, "timezone", current.Timezone)
	locale := stringPatch(patch, "locale", current.Locale)
	avatarURL := stringPatch(patch, "avatar_url", current.AvatarURL)
	phone := stringPatch(patch, "phone", current.Phone)
	birthdate := current.Birthdate
	if raw, ok := patch["birthdate"]; ok {
		birthdate = parseOptionalDate(fmt.Sprint(raw))
	}
	metadata := current.Metadata
	if raw, ok := patch["metadata"]; ok {
		metadata = domain.RawJSON(raw)
	}
	_, err = tx.ExecContext(ctx, `
update user_profiles
set full_name=$3,display_name=$4,bio=$5,birthdate=$6,gender=$7,timezone=$8,locale=$9,avatar_url=$10,phone=$11,metadata=$12,updated_at=now()
where tenant=$1 and user_id=$2 and deleted_at is null`, tenant, userID, fullName, displayName, bio, nullTimePtr(birthdate), gender, timezone, locale, avatarURL, phone, metadata)
	if err != nil {
		return domain.UserProfile{}, err
	}
	if err := r.insertOutboxTx(ctx, tx, event, r.cfg.KafkaEventsTopic); err != nil {
		return domain.UserProfile{}, err
	}
	_ = r.insertActivityTx(ctx, tx, eventActivity(event, "profile updated"))
	if err := tx.Commit(); err != nil {
		return domain.UserProfile{}, err
	}
	return r.GetProfile(ctx, tenant, userID)
}

func (r *PostgresRepository) GetPreferences(ctx context.Context, tenant, userID string, defaults ProfileDefaults) (domain.Preferences, error) {
	_, _ = r.db.ExecContext(ctx, `
insert into user_preferences(tenant, user_id, timezone, locale, theme, notifications_enabled, metadata, created_at, updated_at)
values($1,$2,$3,$4,$5,true,'{}',now(),now())
on conflict(tenant, user_id) do nothing`, tenant, userID, defaults.Timezone, defaults.Locale, defaults.Theme)
	row := r.db.QueryRowContext(ctx, `
select tenant,user_id,timezone,locale,theme,notifications_enabled,notification_settings,dashboard_settings,report_settings,privacy_settings,access_request_settings,metadata,created_at,updated_at
from user_preferences where tenant=$1 and user_id=$2 and deleted_at is null`, tenant, userID)
	return scanPreferences(row)
}

func scanPreferences(row interface{ Scan(dest ...any) error }) (domain.Preferences, error) {
	var p domain.Preferences
	var notificationSettings, dashboardSettings, reportSettings, privacySettings, accessRequestSettings, metadata []byte
	if err := row.Scan(&p.Tenant, &p.UserID, &p.Timezone, &p.Locale, &p.Theme, &p.NotificationsEnabled, &notificationSettings, &dashboardSettings, &reportSettings, &privacySettings, &accessRequestSettings, &metadata, &p.CreatedAt, &p.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return domain.Preferences{}, ErrNotFound
		}
		return domain.Preferences{}, err
	}
	p.NotificationSettings = emptyJSON(notificationSettings, "{}")
	p.DashboardSettings = emptyJSON(dashboardSettings, "{}")
	p.ReportSettings = emptyJSON(reportSettings, "{}")
	p.PrivacySettings = emptyJSON(privacySettings, "{}")
	p.AccessRequestSettings = emptyJSON(accessRequestSettings, "{}")
	p.Metadata = emptyJSON(metadata, "{}")
	return p, nil
}

func (r *PostgresRepository) PutPreferences(ctx context.Context, tenant, userID string, patch map[string]any, event domain.EventEnvelope) (domain.Preferences, error) {
	timezone := valueString(patch["timezone"], r.cfg.DefaultTimezone)
	locale := valueString(patch["locale"], r.cfg.DefaultLocale)
	theme := valueString(patch["theme"], r.cfg.DefaultTheme)
	notifications := valueBool(patch["notifications_enabled"], true)
	notificationSettings := jsonPatch(patch, "notification_settings", domain.EmptyObject())
	dashboardSettings := jsonPatch(patch, "dashboard_settings", domain.EmptyObject())
	reportSettings := jsonPatch(patch, "report_settings", domain.EmptyObject())
	privacySettings := jsonPatch(patch, "privacy_settings", domain.EmptyObject())
	accessRequestSettings := jsonPatch(patch, "access_request_settings", domain.EmptyObject())
	metadata := domain.EmptyObject()
	if raw, ok := patch["metadata"]; ok {
		metadata = domain.RawJSON(raw)
	}
	tx, err := r.db.BeginTx(ctx, &sql.TxOptions{})
	if err != nil {
		return domain.Preferences{}, err
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(ctx, `
insert into user_preferences(tenant,user_id,timezone,locale,theme,notifications_enabled,notification_settings,dashboard_settings,report_settings,privacy_settings,access_request_settings,metadata,created_at,updated_at)
values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,now(),now())
on conflict(tenant,user_id) do update set timezone=excluded.timezone,locale=excluded.locale,theme=excluded.theme,notifications_enabled=excluded.notifications_enabled,notification_settings=excluded.notification_settings,dashboard_settings=excluded.dashboard_settings,report_settings=excluded.report_settings,privacy_settings=excluded.privacy_settings,access_request_settings=excluded.access_request_settings,metadata=excluded.metadata,updated_at=now()`, tenant, userID, timezone, locale, theme, notifications, notificationSettings, dashboardSettings, reportSettings, privacySettings, accessRequestSettings, metadata)
	if err != nil {
		return domain.Preferences{}, err
	}
	if err := r.insertOutboxTx(ctx, tx, event, r.cfg.KafkaEventsTopic); err != nil {
		return domain.Preferences{}, err
	}
	_ = r.insertActivityTx(ctx, tx, eventActivity(event, "preferences updated"))
	if err := tx.Commit(); err != nil {
		return domain.Preferences{}, err
	}
	return r.GetPreferences(ctx, tenant, userID, ProfileDefaults{Timezone: r.cfg.DefaultTimezone, Locale: r.cfg.DefaultLocale, Theme: r.cfg.DefaultTheme})
}

func (r *PostgresRepository) ListActivity(ctx context.Context, tenant, userID string, page Page) ([]domain.ActivityEvent, error) {
	rows, err := r.db.QueryContext(ctx, `
select id,coalesce(event_id,''),tenant,user_id,actor_id,coalesce(target_user_id,''),event_type,coalesce(resource_type,''),coalesce(resource_id,''),coalesce(source_service,''),aggregate_type,aggregate_id,summary,payload,coalesce(request_id,''),coalesce(trace_id,''),coalesce(correlation_id,''),metadata,created_at
from user_activity_events where tenant=$1 and user_id=$2 and deleted_at is null
order by created_at desc limit $3 offset $4`, tenant, userID, page.Limit, page.Offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanActivities(rows)
}

func scanActivities(rows *sql.Rows) ([]domain.ActivityEvent, error) {
	out := make([]domain.ActivityEvent, 0)
	for rows.Next() {
		var a domain.ActivityEvent
		var payload, metadata []byte
		if err := rows.Scan(&a.ID, &a.EventID, &a.Tenant, &a.UserID, &a.ActorID, &a.TargetUserID, &a.EventType, &a.ResourceType, &a.ResourceID, &a.SourceService, &a.AggregateType, &a.AggregateID, &a.Summary, &payload, &a.RequestID, &a.TraceID, &a.CorrelationID, &metadata, &a.CreatedAt); err != nil {
			return nil, err
		}
		a.Payload = emptyJSON(payload, "{}")
		a.Metadata = emptyJSON(metadata, "{}")
		out = append(out, a)
	}
	return out, rows.Err()
}

func (r *PostgresRepository) Dashboard(ctx context.Context, tenant, userID string, defaults ProfileDefaults) (domain.Dashboard, error) {
	profile, err := r.GetProfile(ctx, tenant, userID)
	if err != nil {
		return domain.Dashboard{}, err
	}
	prefs, err := r.GetPreferences(ctx, tenant, userID, defaults)
	if err != nil {
		return domain.Dashboard{}, err
	}
	calc, _ := countByStatus(ctx, r.db, `select coalesce(status,'UNKNOWN'), count(*) from user_calculation_projections where tenant=$1 and user_id=$2 and deleted_at is null group by status`, tenant, userID)
	todos, _ := countByStatus(ctx, r.db, `select coalesce(status,'UNKNOWN'), count(*) from user_todo_projections where tenant=$1 and user_id=$2 and deleted_at is null group by status`, tenant, userID)
	reports, _ := countByStatus(ctx, r.db, `select coalesce(status,'UNKNOWN'), count(*) from user_report_requests where tenant=$1 and target_user_id=$2 and deleted_at is null group by status`, tenant, userID)
	access, _ := countByStatus(ctx, r.db, `select coalesce(status,'UNKNOWN'), count(*) from user_access_grants where tenant=$1 and (requester_user_id=$2 or target_user_id=$2) and deleted_at is null group by status`, tenant, userID)
	return domain.Dashboard{Tenant: tenant, UserID: userID, Profile: profile, Preferences: prefs, Calculations: calc, Todos: todos, Reports: reports, Access: access, GeneratedAt: time.Now().UTC()}, nil
}

func countByStatus(ctx context.Context, db *sql.DB, query, tenant, userID string) (map[string]int, error) {
	rows, err := db.QueryContext(ctx, query, tenant, userID)
	if err != nil {
		return map[string]int{}, err
	}
	defer rows.Close()
	out := map[string]int{}
	for rows.Next() {
		var key string
		var count int
		if err := rows.Scan(&key, &count); err != nil {
			return out, err
		}
		out[strings.ToLower(key)] = count
	}
	return out, rows.Err()
}

func stringPatch(patch map[string]any, key, fallback string) string {
	if v, ok := patch[key]; ok && v != nil {
		return strings.TrimSpace(fmt.Sprint(v))
	}
	return fallback
}

func valueString(v any, fallback string) string {
	if v == nil {
		return fallback
	}
	s := strings.TrimSpace(fmt.Sprint(v))
	if s == "" {
		return fallback
	}
	return s
}

func jsonPatch(patch map[string]any, key string, fallback json.RawMessage) json.RawMessage {
	if raw, ok := patch[key]; ok {
		return domain.RawJSON(raw)
	}
	return fallback
}

func valueBool(v any, fallback bool) bool {
	switch t := v.(type) {
	case bool:
		return t
	case string:
		return strings.EqualFold(t, "true")
	default:
		return fallback
	}
}

func parseOptionalDate(value string) *time.Time {
	value = strings.TrimSpace(value)
	if value == "" || strings.EqualFold(value, "null") {
		return nil
	}
	if t, err := time.Parse("2006-01-02", value); err == nil {
		utc := t.UTC()
		return &utc
	}
	if t, err := time.Parse(time.RFC3339, value); err == nil {
		utc := t.UTC()
		return &utc
	}
	return nil
}

func NewActivity(tenant, userID, actorID, eventType, aggregateType, aggregateID, summary string, payload any) domain.ActivityEvent {
	return domain.ActivityEvent{ID: platform.NewID("act"), Tenant: tenant, UserID: userID, ActorID: actorID, EventType: eventType, ResourceType: aggregateType, ResourceID: aggregateID, AggregateType: aggregateType, AggregateID: aggregateID, Summary: summary, Payload: domain.RawJSON(payload), Metadata: domain.RawJSON(payload), CreatedAt: time.Now().UTC()}
}

func toRawMap(m map[string]any) json.RawMessage { return domain.RawJSON(m) }
