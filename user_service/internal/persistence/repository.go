package persistence

import (
	"context"
	"time"

	"user_service/internal/domain"
)

type Page struct {
	Limit  int
	Offset int
}

func NormalizePage(limit, offset int) Page {
	if limit <= 0 {
		limit = 50
	}
	if limit > 100 {
		limit = 100
	}
	if offset < 0 {
		offset = 0
	}
	return Page{Limit: limit, Offset: offset}
}

type Repository interface {
	Close() error
	Ping(ctx context.Context) error
	Migrate(ctx context.Context, migrationsDir string) error
	PendingOutboxCount(ctx context.Context) (int, error)

	EnsureProfile(ctx context.Context, claims domain.Claims, defaults ProfileDefaults) (domain.UserProfile, error)
	GetProfile(ctx context.Context, tenant, userID string) (domain.UserProfile, error)
	UpdateProfile(ctx context.Context, tenant, userID string, patch map[string]any, event domain.EventEnvelope) (domain.UserProfile, error)
	GetPreferences(ctx context.Context, tenant, userID string, defaults ProfileDefaults) (domain.Preferences, error)
	PutPreferences(ctx context.Context, tenant, userID string, patch map[string]any, event domain.EventEnvelope) (domain.Preferences, error)
	ListActivity(ctx context.Context, tenant, userID string, page Page) ([]domain.ActivityEvent, error)
	Dashboard(ctx context.Context, tenant, userID string, defaults ProfileDefaults) (domain.Dashboard, error)

	ListCalculations(ctx context.Context, tenant, userID string, page Page) ([]domain.CalculationProjection, error)
	GetCalculation(ctx context.Context, tenant, userID, calculationID string) (domain.CalculationProjection, error)
	ListTodos(ctx context.Context, tenant, userID string, page Page) ([]domain.TodoProjection, error)
	GetTodo(ctx context.Context, tenant, userID, todoID string) (domain.TodoProjection, error)
	TodoSummary(ctx context.Context, tenant, userID string) (map[string]int, error)
	ListTodoActivity(ctx context.Context, tenant, userID string, page Page) ([]domain.ActivityEvent, error)

	CreateAccessRequest(ctx context.Context, request domain.AccessRequest, event domain.EventEnvelope) (domain.AccessRequest, error)
	ListAccessRequests(ctx context.Context, tenant, requesterID string, page Page) ([]domain.AccessRequest, error)
	GetAccessRequest(ctx context.Context, tenant, requesterID, requestID string) (domain.AccessRequest, error)
	GetAccessRequestByID(ctx context.Context, tenant, requestID string) (domain.AccessRequest, error)
	CancelAccessRequest(ctx context.Context, tenant, requesterID, requestID string, event domain.EventEnvelope) (domain.AccessRequest, error)
	CancelAccessRequestByID(ctx context.Context, tenant, requestID string, event domain.EventEnvelope) (domain.AccessRequest, error)
	ListVisibleGrants(ctx context.Context, tenant string, claims domain.Claims, page Page) ([]domain.AccessGrant, error)
	HasActiveGrant(ctx context.Context, tenant, actorUserID, targetUserID, resourceType, requiredScope string, at time.Time) (bool, error)

	CreateReportRequest(ctx context.Context, report domain.ReportRequest, event domain.EventEnvelope) (domain.ReportRequest, error)
	ListReportRequests(ctx context.Context, tenant, requesterID, targetUserID string, page Page) ([]domain.ReportRequest, error)
	GetReportRequest(ctx context.Context, tenant, requesterID, targetUserID, reportID string) (domain.ReportRequest, error)
	CancelReportRequest(ctx context.Context, tenant, requesterID, targetUserID, reportID string, event domain.EventEnvelope) (domain.ReportRequest, error)

	LockOutboxBatch(ctx context.Context, limit int) ([]domain.OutboxEvent, error)
	MarkOutboxSent(ctx context.Context, id string) error
	MarkOutboxFailed(ctx context.Context, id, message string, maxAttempts int) error
	ProcessInboundEvent(ctx context.Context, topic string, partition int, offset int64, envelope domain.EventEnvelope) error
}

type ProfileDefaults struct {
	Timezone string
	Locale   string
	Theme    string
}
