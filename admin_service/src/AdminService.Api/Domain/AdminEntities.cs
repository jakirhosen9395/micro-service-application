using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace AdminService.Api.Domain;

public abstract class EntityBase
{
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Column("tenant")]
    public string Tenant { get; set; } = string.Empty;

    [Column("created_at")]
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    [Column("updated_at")]
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    [Column("deleted_at")]
    public DateTimeOffset? DeletedAt { get; set; }
}

public sealed class AdminProfile : EntityBase
{
    [Column("admin_user_id")]
    public string AdminUserId { get; set; } = string.Empty;

    [Column("username")]
    public string Username { get; set; } = string.Empty;

    [Column("email")]
    public string Email { get; set; } = string.Empty;

    [Column("full_name")]
    public string FullName { get; set; } = string.Empty;

    [Column("role")]
    public string Role { get; set; } = "admin";

    [Column("admin_status")]
    public string AdminStatus { get; set; } = "approved";

    [Column("status")]
    public string Status { get; set; } = "active";

    [Column("source")]
    public string Source { get; set; } = "auth_service";

    [Column("is_super_admin")]
    public bool IsSuperAdmin { get; set; }
}

public sealed class AdminRegistrationRequest : EntityBase
{
    [Column("request_id")]
    public string RequestId { get; set; } = string.Empty;

    [Column("user_id")]
    public string UserId { get; set; } = string.Empty;

    [Column("username")]
    public string Username { get; set; } = string.Empty;

    [Column("email")]
    public string Email { get; set; } = string.Empty;

    [Column("full_name")]
    public string FullName { get; set; } = string.Empty;

    [Column("birthdate")]
    public DateOnly? Birthdate { get; set; }

    [Column("gender")]
    public string? Gender { get; set; }

    [Column("reason")]
    public string Reason { get; set; } = string.Empty;

    [Column("status")]
    public string Status { get; set; } = DecisionStatuses.Pending;

    [Column("requested_at")]
    public DateTimeOffset RequestedAt { get; set; } = DateTimeOffset.UtcNow;

    [Column("reviewed_by")]
    public string? ReviewedBy { get; set; }

    [Column("reviewed_at")]
    public DateTimeOffset? ReviewedAt { get; set; }

    [Column("decision_reason")]
    public string? DecisionReason { get; set; }
}

public sealed class AdminAccessRequest : EntityBase
{
    [Column("request_id")]
    public string RequestId { get; set; } = string.Empty;

    [Column("requester_user_id")]
    public string RequesterUserId { get; set; } = string.Empty;

    [Column("target_user_id")]
    public string TargetUserId { get; set; } = string.Empty;

    [Column("resource_type")]
    public string ResourceType { get; set; } = string.Empty;

    [Column("scope")]
    public string Scope { get; set; } = string.Empty;

    [Column("reason")]
    public string Reason { get; set; } = string.Empty;

    [Column("status")]
    public string Status { get; set; } = DecisionStatuses.Pending;

    [Column("requested_at")]
    public DateTimeOffset RequestedAt { get; set; } = DateTimeOffset.UtcNow;

    [Column("requested_by")]
    public string? RequestedBy { get; set; }

    [Column("reviewed_by")]
    public string? ReviewedBy { get; set; }

    [Column("reviewed_at")]
    public DateTimeOffset? ReviewedAt { get; set; }

    [Column("decision_reason")]
    public string? DecisionReason { get; set; }

    [Column("expires_at")]
    public DateTimeOffset? ExpiresAt { get; set; }
}

public sealed class AdminAccessGrant : EntityBase
{
    [Column("grant_id")]
    public string GrantId { get; set; } = string.Empty;

    [Column("request_id")]
    public string RequestId { get; set; } = string.Empty;

    [Column("requester_user_id")]
    public string RequesterUserId { get; set; } = string.Empty;

    [Column("target_user_id")]
    public string TargetUserId { get; set; } = string.Empty;

    [Column("resource_type")]
    public string ResourceType { get; set; } = string.Empty;

    [Column("scope")]
    public string Scope { get; set; } = string.Empty;

    [Column("status")]
    public string Status { get; set; } = GrantStatuses.Active;

    [Column("approved_by")]
    public string ApprovedBy { get; set; } = string.Empty;

    [Column("approved_at")]
    public DateTimeOffset ApprovedAt { get; set; } = DateTimeOffset.UtcNow;

    [Column("expires_at")]
    public DateTimeOffset ExpiresAt { get; set; }

    [Column("revoked_by")]
    public string? RevokedBy { get; set; }

    [Column("revoked_at")]
    public DateTimeOffset? RevokedAt { get; set; }

    [Column("revoke_reason")]
    public string? RevokeReason { get; set; }
}

public sealed class AdminUserProjection : EntityBase
{
    [Column("user_id")]
    public string UserId { get; set; } = string.Empty;

    [Column("username")]
    public string Username { get; set; } = string.Empty;

    [Column("email")]
    public string Email { get; set; } = string.Empty;

    [Column("full_name")]
    public string FullName { get; set; } = string.Empty;

    [Column("role")]
    public string Role { get; set; } = "user";

    [Column("admin_status")]
    public string AdminStatus { get; set; } = "not_requested";

    [Column("status")]
    public string Status { get; set; } = "active";

    [Column("last_seen_at")]
    public DateTimeOffset? LastSeenAt { get; set; }

    [Column("payload")]
    public string Payload { get; set; } = "{}";
}

public sealed class AdminCalculationProjection : EntityBase
{
    [Column("calculation_id")]
    public string CalculationId { get; set; } = string.Empty;

    [Column("user_id")]
    public string UserId { get; set; } = string.Empty;

    [Column("status")]
    public string Status { get; set; } = string.Empty;

    [Column("operation")]
    public string Operation { get; set; } = string.Empty;

    [Column("occurred_at")]
    public DateTimeOffset OccurredAt { get; set; } = DateTimeOffset.UtcNow;

    [Column("payload")]
    public string Payload { get; set; } = "{}";
}

public sealed class AdminTodoProjection : EntityBase
{
    [Column("todo_id")]
    public string TodoId { get; set; } = string.Empty;

    [Column("user_id")]
    public string UserId { get; set; } = string.Empty;

    [Column("status")]
    public string Status { get; set; } = string.Empty;

    [Column("title")]
    public string Title { get; set; } = string.Empty;

    [Column("occurred_at")]
    public DateTimeOffset OccurredAt { get; set; } = DateTimeOffset.UtcNow;

    [Column("payload")]
    public string Payload { get; set; } = "{}";
}

public sealed class AdminReportProjection : EntityBase
{
    [Column("report_id")]
    public string ReportId { get; set; } = string.Empty;

    [Column("user_id")]
    public string UserId { get; set; } = string.Empty;

    [Column("report_type")]
    public string ReportType { get; set; } = string.Empty;

    [Column("format")]
    public string Format { get; set; } = string.Empty;

    [Column("status")]
    public string Status { get; set; } = string.Empty;

    [Column("requested_by")]
    public string RequestedBy { get; set; } = string.Empty;

    [Column("requested_at")]
    public DateTimeOffset RequestedAt { get; set; } = DateTimeOffset.UtcNow;

    [Column("payload")]
    public string Payload { get; set; } = "{}";
}

public sealed class AdminAuditEvent
{
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Column("event_id")]
    public string EventId { get; set; } = string.Empty;

    [Column("tenant")]
    public string Tenant { get; set; } = string.Empty;

    [Column("admin_user_id")]
    public string AdminUserId { get; set; } = string.Empty;

    [Column("target_user_id")]
    public string? TargetUserId { get; set; }

    [Column("event_type")]
    public string EventType { get; set; } = string.Empty;

    [Column("resource_type")]
    public string ResourceType { get; set; } = string.Empty;

    [Column("resource_id")]
    public string ResourceId { get; set; } = string.Empty;

    [Column("request_id")]
    public string RequestId { get; set; } = string.Empty;

    [Column("trace_id")]
    public string TraceId { get; set; } = string.Empty;

    [Column("correlation_id")]
    public string CorrelationId { get; set; } = string.Empty;

    [Column("client_ip")]
    public string? ClientIp { get; set; }

    [Column("user_agent")]
    public string? UserAgent { get; set; }

    [Column("payload")]
    public string Payload { get; set; } = "{}";

    [Column("s3_object_key")]
    public string? S3ObjectKey { get; set; }

    [Column("created_at")]
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class OutboxEvent
{
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Column("event_id")]
    public string EventId { get; set; } = string.Empty;

    [Column("tenant")]
    public string Tenant { get; set; } = string.Empty;

    [Column("aggregate_type")]
    public string AggregateType { get; set; } = string.Empty;

    [Column("aggregate_id")]
    public string AggregateId { get; set; } = string.Empty;

    [Column("event_type")]
    public string EventType { get; set; } = string.Empty;

    [Column("event_version")]
    public string EventVersion { get; set; } = "1.0";

    [Column("topic")]
    public string Topic { get; set; } = string.Empty;

    [Column("payload")]
    public string Payload { get; set; } = "{}";

    [Column("status")]
    public string Status { get; set; } = OutboxStatuses.Pending;

    [Column("attempt_count")]
    public int AttemptCount { get; set; }

    [Column("last_error")]
    public string? LastError { get; set; }

    [Column("next_retry_at")]
    public DateTimeOffset? NextRetryAt { get; set; }

    [Column("request_id")]
    public string? RequestId { get; set; }

    [Column("trace_id")]
    public string? TraceId { get; set; }

    [Column("correlation_id")]
    public string? CorrelationId { get; set; }

    [Column("created_at")]
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    [Column("updated_at")]
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    [Column("sent_at")]
    public DateTimeOffset? SentAt { get; set; }
}

public sealed class KafkaInboxEvent
{
    [Key]
    [Column("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Column("event_id")]
    public string EventId { get; set; } = string.Empty;

    [Column("tenant")]
    public string? Tenant { get; set; }

    [Column("topic")]
    public string Topic { get; set; } = string.Empty;

    [Column("partition")]
    public int Partition { get; set; }

    [Column("offset_value")]
    public long OffsetValue { get; set; }

    [Column("event_type")]
    public string EventType { get; set; } = string.Empty;

    [Column("source_service")]
    public string? SourceService { get; set; }

    [Column("payload")]
    public string? Payload { get; set; }

    [Column("status")]
    public string Status { get; set; } = InboxStatuses.Received;

    [Column("processed_at")]
    public DateTimeOffset? ProcessedAt { get; set; }

    [Column("error_message")]
    public string? ErrorMessage { get; set; }

    [Column("created_at")]
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public static class DecisionStatuses
{
    public const string Pending = "pending";
    public const string Approved = "approved";
    public const string Rejected = "rejected";
    public const string Cancelled = "cancelled";
}

public static class GrantStatuses
{
    public const string Active = "active";
    public const string Revoked = "revoked";
    public const string Expired = "expired";
}

public static class OutboxStatuses
{
    public const string Pending = "PENDING";
    public const string Processing = "PROCESSING";
    public const string Sent = "SENT";
    public const string Failed = "FAILED";
    public const string DeadLettered = "DEAD_LETTERED";
}

public static class InboxStatuses
{
    public const string Received = "RECEIVED";
    public const string Processing = "PROCESSING";
    public const string Processed = "PROCESSED";
    public const string Failed = "FAILED";
    public const string Ignored = "IGNORED";
}
