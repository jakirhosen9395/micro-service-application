package domain

import (
	"encoding/json"
	"time"
)

const (
	StatusPending   = "PENDING"
	StatusActive    = "ACTIVE"
	StatusApproved  = "APPROVED"
	StatusRejected  = "REJECTED"
	StatusCancelled = "CANCELLED"
	StatusRevoked   = "REVOKED"
	StatusQueued    = "QUEUED"
)

type Claims struct {
	Subject     string `json:"sub"`
	JTI         string `json:"jti"`
	Username    string `json:"username"`
	Email       string `json:"email"`
	Role        string `json:"role"`
	AdminStatus string `json:"admin_status"`
	Tenant      string `json:"tenant"`
	Issuer      string `json:"iss"`
	Audience    string `json:"aud"`
	Status      string `json:"status,omitempty"`
	IssuedAt    int64  `json:"iat"`
	NotBefore   int64  `json:"nbf"`
	ExpiresAt   int64  `json:"exp"`
}

func (c Claims) IsApprovedAdmin() bool {
	return c.Role == "admin" && c.AdminStatus == "approved" && (c.Status == "" || c.Status == "active")
}

func (c Claims) IsService() bool {
	return c.Role == "service" || c.Role == "system"
}

type RequestMeta struct {
	RequestID     string
	TraceID       string
	CorrelationID string
	ClientIP      string
	UserAgent     string
}

type UserProfile struct {
	ID            string          `json:"id"`
	Tenant        string          `json:"tenant"`
	UserID        string          `json:"user_id"`
	Username      string          `json:"username"`
	Email         string          `json:"email"`
	FullName      string          `json:"full_name"`
	DisplayName   string          `json:"display_name,omitempty"`
	Bio           string          `json:"bio,omitempty"`
	Birthdate     *time.Time      `json:"birthdate,omitempty"`
	Gender        string          `json:"gender,omitempty"`
	Role          string          `json:"role"`
	AdminStatus   string          `json:"admin_status"`
	Status        string          `json:"status"`
	Timezone      string          `json:"timezone"`
	Locale        string          `json:"locale"`
	AvatarURL     string          `json:"avatar_url,omitempty"`
	Phone         string          `json:"phone,omitempty"`
	SourceEventID string          `json:"source_event_id,omitempty"`
	LastSeenAt    *time.Time      `json:"last_seen_at,omitempty"`
	Metadata      json.RawMessage `json:"metadata,omitempty"`
	CreatedAt     time.Time       `json:"created_at"`
	UpdatedAt     time.Time       `json:"updated_at"`
}

type Preferences struct {
	Tenant                string          `json:"tenant"`
	UserID                string          `json:"user_id"`
	Timezone              string          `json:"timezone"`
	Locale                string          `json:"locale"`
	Theme                 string          `json:"theme"`
	NotificationsEnabled  bool            `json:"notifications_enabled"`
	NotificationSettings  json.RawMessage `json:"notification_settings,omitempty"`
	DashboardSettings     json.RawMessage `json:"dashboard_settings,omitempty"`
	ReportSettings        json.RawMessage `json:"report_settings,omitempty"`
	PrivacySettings       json.RawMessage `json:"privacy_settings,omitempty"`
	AccessRequestSettings json.RawMessage `json:"access_request_settings,omitempty"`
	Metadata              json.RawMessage `json:"metadata,omitempty"`
	CreatedAt             time.Time       `json:"created_at"`
	UpdatedAt             time.Time       `json:"updated_at"`
}

type ActivityEvent struct {
	ID            string          `json:"id"`
	EventID       string          `json:"event_id,omitempty"`
	Tenant        string          `json:"tenant"`
	UserID        string          `json:"user_id"`
	ActorID       string          `json:"actor_id"`
	TargetUserID  string          `json:"target_user_id,omitempty"`
	EventType     string          `json:"event_type"`
	ResourceType  string          `json:"resource_type,omitempty"`
	ResourceID    string          `json:"resource_id,omitempty"`
	SourceService string          `json:"source_service,omitempty"`
	AggregateType string          `json:"aggregate_type"`
	AggregateID   string          `json:"aggregate_id"`
	Summary       string          `json:"summary"`
	Payload       json.RawMessage `json:"payload,omitempty"`
	RequestID     string          `json:"request_id,omitempty"`
	TraceID       string          `json:"trace_id,omitempty"`
	CorrelationID string          `json:"correlation_id,omitempty"`
	Metadata      json.RawMessage `json:"metadata,omitempty"`
	CreatedAt     time.Time       `json:"created_at"`
}

type CalculationProjection struct {
	Tenant        string          `json:"tenant"`
	CalculationID string          `json:"calculation_id"`
	UserID        string          `json:"user_id"`
	Operation     string          `json:"operation,omitempty"`
	Expression    string          `json:"expression,omitempty"`
	Operands      json.RawMessage `json:"operands,omitempty"`
	Result        string          `json:"result,omitempty"`
	Status        string          `json:"status"`
	ErrorMessage  string          `json:"error_message,omitempty"`
	SourceEventID string          `json:"source_event_id,omitempty"`
	OccurredAt    time.Time       `json:"occurred_at"`
	Metadata      json.RawMessage `json:"metadata,omitempty"`
	S3ObjectKey   string          `json:"s3_object_key,omitempty"`
	CreatedAt     time.Time       `json:"created_at"`
	UpdatedAt     time.Time       `json:"updated_at"`
}

type TodoProjection struct {
	Tenant        string          `json:"tenant"`
	TodoID        string          `json:"todo_id"`
	UserID        string          `json:"user_id"`
	Title         string          `json:"title"`
	Description   string          `json:"description,omitempty"`
	Status        string          `json:"status"`
	Priority      string          `json:"priority"`
	DueDate       *time.Time      `json:"due_date,omitempty"`
	Tags          json.RawMessage `json:"tags,omitempty"`
	CompletedAt   *time.Time      `json:"completed_at,omitempty"`
	ArchivedAt    *time.Time      `json:"archived_at,omitempty"`
	SourceEventID string          `json:"source_event_id,omitempty"`
	Metadata      json.RawMessage `json:"metadata,omitempty"`
	CreatedAt     time.Time       `json:"created_at"`
	UpdatedAt     time.Time       `json:"updated_at"`
}

type AccessRequest struct {
	Tenant          string          `json:"tenant"`
	RequestID       string          `json:"request_id"`
	RequesterUserID string          `json:"requester_user_id"`
	TargetUserID    string          `json:"target_user_id"`
	ResourceType    string          `json:"resource_type"`
	Scope           string          `json:"scope"`
	Reason          string          `json:"reason"`
	Status          string          `json:"status"`
	ExpiresAt       time.Time       `json:"expires_at"`
	DecisionReason  string          `json:"decision_reason,omitempty"`
	DecidedBy       string          `json:"decided_by,omitempty"`
	DecidedAt       *time.Time      `json:"decided_at,omitempty"`
	CancelledAt     *time.Time      `json:"cancelled_at,omitempty"`
	Metadata        json.RawMessage `json:"metadata,omitempty"`
	CreatedAt       time.Time       `json:"created_at"`
	UpdatedAt       time.Time       `json:"updated_at"`
}

type AccessGrant struct {
	Tenant          string          `json:"tenant"`
	GrantID         string          `json:"grant_id"`
	RequestID       string          `json:"request_id,omitempty"`
	RequesterUserID string          `json:"requester_user_id"`
	TargetUserID    string          `json:"target_user_id"`
	ResourceType    string          `json:"resource_type"`
	Scope           string          `json:"scope"`
	Status          string          `json:"status"`
	ApprovedBy      string          `json:"approved_by,omitempty"`
	RevokedBy       string          `json:"revoked_by,omitempty"`
	Reason          string          `json:"reason,omitempty"`
	ExpiresAt       time.Time       `json:"expires_at"`
	RevokedAt       *time.Time      `json:"revoked_at,omitempty"`
	Metadata        json.RawMessage `json:"metadata,omitempty"`
	CreatedAt       time.Time       `json:"created_at"`
	UpdatedAt       time.Time       `json:"updated_at"`
}

type ReportRequest struct {
	Tenant          string          `json:"tenant"`
	ReportID        string          `json:"report_id"`
	RequesterUserID string          `json:"requester_user_id"`
	TargetUserID    string          `json:"target_user_id"`
	ReportType      string          `json:"report_type"`
	Format          string          `json:"format"`
	DateFrom        *time.Time      `json:"date_from,omitempty"`
	DateTo          *time.Time      `json:"date_to,omitempty"`
	Filters         json.RawMessage `json:"filters,omitempty"`
	Options         json.RawMessage `json:"options,omitempty"`
	Status          string          `json:"status"`
	FileName        string          `json:"file_name,omitempty"`
	S3ObjectKey     string          `json:"s3_object_key,omitempty"`
	DownloadURL     string          `json:"download_url,omitempty"`
	ErrorMessage    string          `json:"error_message,omitempty"`
	ExpiresAt       *time.Time      `json:"expires_at,omitempty"`
	CreatedAt       time.Time       `json:"created_at"`
	UpdatedAt       time.Time       `json:"updated_at"`
}

type ReportProjection struct {
	Tenant          string          `json:"tenant"`
	ReportID        string          `json:"report_id"`
	RequesterUserID string          `json:"requester_user_id"`
	TargetUserID    string          `json:"target_user_id"`
	ReportType      string          `json:"report_type"`
	Format          string          `json:"format"`
	Status          string          `json:"status"`
	FileName        string          `json:"file_name,omitempty"`
	S3ObjectKey     string          `json:"s3_object_key,omitempty"`
	DownloadURL     string          `json:"download_url,omitempty"`
	ErrorMessage    string          `json:"error_message,omitempty"`
	ExpiresAt       *time.Time      `json:"expires_at,omitempty"`
	Metadata        json.RawMessage `json:"metadata,omitempty"`
	SourceEventID   string          `json:"source_event_id,omitempty"`
	CreatedAt       time.Time       `json:"created_at"`
	UpdatedAt       time.Time       `json:"updated_at"`
}

type Dashboard struct {
	Tenant       string         `json:"tenant"`
	UserID       string         `json:"user_id"`
	Profile      UserProfile    `json:"profile"`
	Preferences  Preferences    `json:"preferences"`
	Calculations map[string]int `json:"calculations"`
	Todos        map[string]int `json:"todos"`
	Reports      map[string]int `json:"reports"`
	Access       map[string]int `json:"access"`
	GeneratedAt  time.Time      `json:"generated_at"`
}

type ReportType struct {
	ReportType  string   `json:"report_type"`
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Formats     []string `json:"formats"`
	Scopes      []string `json:"required_scopes"`
}

type EventEnvelope struct {
	EventID       string          `json:"event_id"`
	EventType     string          `json:"event_type"`
	EventVersion  string          `json:"event_version"`
	Service       string          `json:"service"`
	Environment   string          `json:"environment"`
	Tenant        string          `json:"tenant"`
	Timestamp     string          `json:"timestamp"`
	RequestID     string          `json:"request_id"`
	TraceID       string          `json:"trace_id"`
	CorrelationID string          `json:"correlation_id"`
	UserID        string          `json:"user_id"`
	ActorID       string          `json:"actor_id"`
	AggregateType string          `json:"aggregate_type"`
	AggregateID   string          `json:"aggregate_id"`
	Payload       json.RawMessage `json:"payload"`
}

type OutboxEvent struct {
	ID            string
	EventID       string
	Tenant        string
	AggregateType string
	AggregateID   string
	EventType     string
	Topic         string
	Payload       json.RawMessage
	AttemptCount  int
}

type InboxEvent struct {
	EventID       string
	Tenant        string
	Topic         string
	Partition     int
	Offset        int64
	EventType     string
	SourceService string
	Payload       json.RawMessage
}

func RawJSON(v any) json.RawMessage {
	if v == nil {
		return json.RawMessage(`{}`)
	}
	b, err := json.Marshal(v)
	if err != nil {
		return json.RawMessage(`{}`)
	}
	return b
}

func EmptyObject() json.RawMessage { return json.RawMessage(`{}`) }
func EmptyArray() json.RawMessage  { return json.RawMessage(`[]`) }
