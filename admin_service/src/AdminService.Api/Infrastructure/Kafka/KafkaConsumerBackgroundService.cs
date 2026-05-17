using AdminService.Api.Configuration;
using AdminService.Api.Contracts;
using AdminService.Api.Domain;
using AdminService.Api.Http;
using AdminService.Api.Infrastructure.Logging;
using AdminService.Api.Infrastructure.Observability;
using AdminService.Api.Persistence;
using Confluent.Kafka;
using Elastic.Apm;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using System.Text.Json;

namespace AdminService.Api.Infrastructure.Kafka;

public sealed class KafkaConsumerBackgroundService : BackgroundService
{
    private readonly AdminSettings _settings;
    private readonly IDbContextFactory<AdminDbContext> _dbFactory;
    private readonly AppLogger _logger;

    public KafkaConsumerBackgroundService(AdminSettings settings, IDbContextFactory<AdminDbContext> dbFactory, AppLogger logger)
    {
        _settings = settings;
        _dbFactory = dbFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await _logger.InfoAsync("kafka.consumer.started", "Kafka consumer started", extra: new Dictionary<string, object?> { ["group"] = _settings.KafkaConsumerGroup }, cancellationToken: stoppingToken);
        var config = new ConsumerConfig
        {
            BootstrapServers = _settings.KafkaBootstrapServers,
            GroupId = _settings.KafkaConsumerGroup,
            AutoOffsetReset = AutoOffsetReset.Earliest,
            EnableAutoCommit = false,
            EnablePartitionEof = false
        };

        using var consumer = new ConsumerBuilder<string, string>(config).Build();
        consumer.Subscribe(_settings.KafkaConsumeTopics);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var result = consumer.Consume(stoppingToken);
                if (result?.Message?.Value is null) continue;
                await Agent.Tracer.CaptureTransaction($"admin.kafka.consume {result.Topic}", "messaging", async transaction =>
                {
                    transaction.SetLabel("component", "kafka-consumer");
                    transaction.SetLabel("topic", result.Topic);
                    transaction.SetLabel("partition", result.Partition.Value);
                    transaction.SetLabel("offset", result.Offset.Value);
                    transaction.SetLabel("consumer_group", _settings.KafkaConsumerGroup);
                    ApmTelemetry.SetLabel(transaction, "traceparent", HeaderValue(result.Message.Headers, "traceparent"));
                    await ProcessMessageAsync(result, stoppingToken);
                    ApmTelemetry.CaptureSpan(
                        $"Kafka commit {result.Topic}",
                        "messaging",
                        "kafka",
                        "commit",
                        () => consumer.Commit(result),
                        new Dictionary<string, object?>
                        {
                            ["dependency"] = "kafka",
                            ["messaging_system"] = "kafka",
                            ["messaging_operation"] = "commit",
                            ["topic"] = result.Topic,
                            ["partition"] = result.Partition.Value,
                            ["offset"] = result.Offset.Value,
                            ["consumer_group"] = _settings.KafkaConsumerGroup
                        });
                });
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (ConsumeException ex)
            {
                await _logger.ErrorAsync("kafka.consume.failed", "Kafka consume failed", ex, errorCode: "KAFKA_CONSUME_FAILED", cancellationToken: CancellationToken.None);
            }
            catch (Exception ex)
            {
                await _logger.ErrorAsync("kafka.message.process_failed", "Kafka message processing failed", ex, errorCode: "KAFKA_MESSAGE_PROCESS_FAILED", cancellationToken: CancellationToken.None);
            }
        }
    }

    private async Task ProcessMessageAsync(ConsumeResult<string, string> result, CancellationToken cancellationToken)
    {
        EventEnvelope? envelope;
        var deserializeSpan = ApmTelemetry.StartSpan(
            "Kafka deserialize envelope",
            "app",
            "json",
            "deserialize",
            new Dictionary<string, object?>
            {
                ["dependency"] = "kafka",
                ["topic"] = result.Topic,
                ["partition"] = result.Partition.Value,
                ["offset"] = result.Offset.Value,
                ["payload_bytes"] = result.Message.Value.Length
            });
        try
        {
            envelope = JsonSerializer.Deserialize<EventEnvelope>(result.Message.Value, JsonOptionsFactory.Options);
            ApmTelemetry.SetLabel(deserializeSpan, "outcome", "success");
        }
        catch (JsonException ex)
        {
            // Malformed/legacy events are data quality issues, not admin_service crashes.
            // Store the inbox marker and commit the offset without creating an APM error group.
            ApmTelemetry.SetLabel(deserializeSpan, "outcome", "ignored");
            ApmTelemetry.SetLabel(deserializeSpan, "invalid_reason", "invalid-envelope");
            ApmTelemetry.SetLabel(deserializeSpan, "json_error", SecretRedactor.SafeExceptionMessage(ex));
            await StoreInvalidMessageAsync(result, "invalid-envelope", cancellationToken);
            return;
        }
        finally
        {
            ApmTelemetry.EndSpan(deserializeSpan);
        }

        if (envelope is null || string.IsNullOrWhiteSpace(envelope.EventId) || string.IsNullOrWhiteSpace(envelope.EventType))
        {
            await StoreInvalidMessageAsync(result, "missing-event-identity", cancellationToken);
            return;
        }

        if (string.IsNullOrWhiteSpace(envelope.Tenant))
        {
            envelope.Tenant = _settings.Tenant;
        }

        var transaction = Agent.Tracer.CurrentTransaction;
        ApmTelemetry.SetLabel(transaction, "event_id", envelope.EventId);
        ApmTelemetry.SetLabel(transaction, "event_type", envelope.EventType);
        ApmTelemetry.SetLabel(transaction, "source_service", envelope.Service);
        ApmTelemetry.SetLabel(transaction, "tenant", envelope.Tenant);
        ApmTelemetry.SetLabel(transaction, "aggregate_type", envelope.AggregateType);
        ApmTelemetry.SetLabel(transaction, "aggregate_id", envelope.AggregateId);
        ApmTelemetry.SetLabel(transaction, "user_id", envelope.UserId);
        ApmTelemetry.SetLabel(transaction, "request_id", envelope.RequestId);
        ApmTelemetry.SetLabel(transaction, "correlation_id", envelope.CorrelationId);

        if (!string.Equals(envelope.Tenant, _settings.Tenant, StringComparison.Ordinal))
        {
            await _logger.InfoAsync("kafka.message.ignored_tenant", "Kafka message ignored because tenant does not match this service instance", extra: new Dictionary<string, object?>
            {
                ["event_id"] = envelope.EventId,
                ["event_type"] = envelope.EventType,
                ["event_tenant"] = envelope.Tenant,
                ["service_tenant"] = _settings.Tenant,
                ["topic"] = result.Topic
            }, cancellationToken: cancellationToken);
            return;
        }

        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        var exists = await db.KafkaInboxEvents.AnyAsync(x => x.EventId == envelope.EventId || (x.Topic == result.Topic && x.Partition == result.Partition.Value && x.OffsetValue == result.Offset.Value), cancellationToken);
        if (exists) return;

        var inbox = new KafkaInboxEvent
        {
            EventId = envelope.EventId,
            Tenant = envelope.Tenant,
            Topic = result.Topic,
            Partition = result.Partition.Value,
            OffsetValue = result.Offset.Value,
            EventType = envelope.EventType,
            SourceService = envelope.Service,
            Payload = result.Message.Value,
            Status = InboxStatuses.Processing,
            CreatedAt = DateTimeOffset.UtcNow
        };
        db.KafkaInboxEvents.Add(inbox);
        try
        {
            await db.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException ex) when (IsUniqueConstraintViolation(ex))
        {
            await _logger.InfoAsync("kafka.inbox.duplicate_ignored", "Duplicate Kafka inbox message ignored", extra: new Dictionary<string, object?>
            {
                ["event_id"] = envelope.EventId,
                ["event_type"] = envelope.EventType,
                ["topic"] = result.Topic,
                ["partition"] = result.Partition.Value,
                ["offset"] = result.Offset.Value
            }, cancellationToken: cancellationToken);
            return;
        }

        try
        {
            if (string.Equals(envelope.Service, _settings.ServiceName, StringComparison.Ordinal))
            {
                inbox.Status = InboxStatuses.Ignored;
                inbox.ProcessedAt = DateTimeOffset.UtcNow;
            }
            else
            {
                await ApmTelemetry.CaptureSpanAsync(
                    $"Projection {envelope.EventType}",
                    "app",
                    "projection",
                    "upsert",
                    async () => await ApplyProjectionAsync(db, envelope, result.Topic, cancellationToken),
                    new Dictionary<string, object?>
                    {
                        ["event_id"] = envelope.EventId,
                        ["event_type"] = envelope.EventType,
                        ["topic"] = result.Topic,
                        ["tenant"] = envelope.Tenant,
                        ["source_service"] = envelope.Service,
                        ["aggregate_type"] = envelope.AggregateType,
                        ["aggregate_id"] = envelope.AggregateId
                    });
                inbox.Status = InboxStatuses.Processed;
                inbox.ProcessedAt = DateTimeOffset.UtcNow;
            }
        }
        catch (Exception ex)
        {
            inbox.Status = InboxStatuses.Failed;
            inbox.ErrorMessage = SecretRedactor.SafeExceptionMessage(ex);
            await _logger.ErrorAsync("kafka.inbox.projection_failed", "Kafka inbox projection failed", ex, errorCode: "INBOX_PROJECTION_FAILED", extra: new Dictionary<string, object?>
            {
                ["event_id"] = envelope.EventId,
                ["event_type"] = envelope.EventType,
                ["source_service"] = envelope.Service,
                ["topic"] = result.Topic
            }, cancellationToken: cancellationToken);
        }

        await db.SaveChangesAsync(cancellationToken);
    }

    private async Task StoreInvalidMessageAsync(ConsumeResult<string, string> result, string reason, CancellationToken cancellationToken)
    {
        await ApmTelemetry.CaptureSpanAsync(
            "Kafka store invalid message",
            "db",
            "postgresql",
            "insert",
            async () =>
            {
                await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
                var eventId = $"invalid-{result.Topic}-{result.Partition.Value}-{result.Offset.Value}";
                if (await db.KafkaInboxEvents.AnyAsync(x => x.EventId == eventId, cancellationToken)) return;
                db.KafkaInboxEvents.Add(new KafkaInboxEvent
                {
                    EventId = eventId,
                    Tenant = _settings.Tenant,
                    Topic = result.Topic,
                    Partition = result.Partition.Value,
                    OffsetValue = result.Offset.Value,
                    EventType = "invalid",
                    SourceService = null,
                    Payload = null,
                    Status = InboxStatuses.Ignored,
                    ErrorMessage = reason,
                    ProcessedAt = DateTimeOffset.UtcNow
                });

                try
                {
                    await db.SaveChangesAsync(cancellationToken);
                }
                catch (DbUpdateException ex) when (IsUniqueConstraintViolation(ex))
                {
                    // Another service instance or retry already recorded this malformed message.
                }
            },
            new Dictionary<string, object?>
            {
                ["dependency"] = "postgresql",
                ["db_system"] = "postgresql",
                ["db_operation"] = "insert",
                ["table"] = "kafka_inbox_events",
                ["topic"] = result.Topic,
                ["partition"] = result.Partition.Value,
                ["offset"] = result.Offset.Value,
                ["reason"] = reason
            });
    }

    private static string? HeaderValue(Headers? headers, string key)
    {
        if (headers is null) return null;
        try
        {
            var bytes = headers.GetLastBytes(key);
            return bytes is null ? null : System.Text.Encoding.UTF8.GetString(bytes);
        }
        catch
        {
            return null;
        }
    }

    private static bool IsUniqueConstraintViolation(DbUpdateException exception)
        => exception.InnerException is PostgresException postgres && postgres.SqlState == PostgresErrorCodes.UniqueViolation;

    private static async Task ApplyProjectionAsync(AdminDbContext db, EventEnvelope envelope, string topic, CancellationToken cancellationToken)
    {
        var eventType = NormalizeEventName(envelope.EventType);
        if (topic == "auth.admin.requests" || eventType is "auth.admin.requested" or "admin.registration.requested" or "admin.registration.created")
        {
            await UpsertRegistrationAsync(db, envelope, cancellationToken);
            return;
        }

        if (topic == "auth.admin.decisions" || eventType.StartsWith("admin.registration.", StringComparison.Ordinal) || eventType.StartsWith("auth.admin.decision", StringComparison.Ordinal))
        {
            await ApplyRegistrationDecisionAsync(db, envelope, cancellationToken);
            return;
        }

        if (IsAccessRequestEvent(envelope, topic))
        {
            await UpsertAccessRequestAsync(db, envelope, cancellationToken);
            return;
        }

        if (IsAccessGrantEvent(envelope, topic))
        {
            await UpsertAccessGrantAsync(db, envelope, cancellationToken);
            return;
        }

        if (eventType.StartsWith("calculation.", StringComparison.Ordinal))
        {
            await UpsertCalculationAsync(db, envelope, cancellationToken);
            return;
        }

        if (eventType.StartsWith("todo.", StringComparison.Ordinal))
        {
            await UpsertTodoAsync(db, envelope, cancellationToken);
            return;
        }

        if (eventType.StartsWith("report.", StringComparison.Ordinal))
        {
            await UpsertReportAsync(db, envelope, cancellationToken);
            return;
        }

        if (eventType.StartsWith("user.", StringComparison.Ordinal) || eventType.StartsWith("auth.user.", StringComparison.Ordinal) || eventType.StartsWith("auth.signup", StringComparison.Ordinal))
        {
            await UpsertUserAsync(db, envelope, cancellationToken);
        }
    }

    private static async Task UpsertRegistrationAsync(AdminDbContext db, EventEnvelope envelope, CancellationToken ct)
    {
        var p = envelope.Payload;
        var user = Object(p, "user");
        var requestId = Text(p, "request_id", "id") ?? envelope.AggregateId;
        var userId = Text(p, "user_id", "target_user_id") ?? Text(user, "id", "user_id") ?? envelope.UserId ?? envelope.AggregateId;
        var tenant = envelope.Tenant;
        var entity = await db.AdminRegistrationRequests.FirstOrDefaultAsync(x => x.Tenant == tenant && x.RequestId == requestId, ct);
        if (entity is null)
        {
            entity = new AdminRegistrationRequest { Tenant = tenant, RequestId = requestId, UserId = userId };
            db.AdminRegistrationRequests.Add(entity);
        }
        entity.Username = Text(p, "username") ?? Text(user, "username") ?? entity.Username;
        entity.Email = Text(p, "email") ?? Text(user, "email") ?? entity.Email;
        entity.FullName = Text(p, "full_name", "fullName") ?? Text(user, "full_name", "fullName") ?? entity.FullName;
        entity.Gender = Text(p, "gender") ?? Text(user, "gender") ?? entity.Gender;
        entity.Reason = Text(p, "reason", "admin_request_reason") ?? Text(user, "admin_request_reason") ?? entity.Reason;
        entity.Status = Text(p, "decision", "registration_status") ?? DecisionStatuses.Pending;
        entity.RequestedAt = NullableTime(p, "requested_at") ?? NullableTime(user, "admin_requested_at", "created_at") ?? envelope.Timestamp;
        entity.Birthdate = Date(p, "birthdate") ?? Date(user, "birthdate") ?? entity.Birthdate;
    }

    private static async Task ApplyRegistrationDecisionAsync(AdminDbContext db, EventEnvelope envelope, CancellationToken ct)
    {
        var p = envelope.Payload;
        var requestId = Text(p, "request_id", "id") ?? envelope.AggregateId;
        var tenant = envelope.Tenant;
        var entity = await db.AdminRegistrationRequests.FirstOrDefaultAsync(x => x.Tenant == tenant && x.RequestId == requestId, ct);
        if (entity is null) return;
        var status = Text(p, "decision", "status") ?? (envelope.EventType.EndsWith("approved", StringComparison.OrdinalIgnoreCase) ? DecisionStatuses.Approved : DecisionStatuses.Rejected);
        entity.Status = status;
        entity.ReviewedAt = envelope.Timestamp;
        entity.ReviewedBy = Text(p, "reviewed_by", "actor_id") ?? envelope.ActorId;
        entity.DecisionReason = Text(p, "reason") ?? entity.DecisionReason;
    }

    private static async Task UpsertAccessRequestAsync(AdminDbContext db, EventEnvelope envelope, CancellationToken ct)
    {
        var p = envelope.Payload;
        var requestId = Text(p, "request_id", "access_request_id", "id") ?? envelope.AggregateId;
        var tenant = envelope.Tenant;
        var entity = await db.AdminAccessRequests.FirstOrDefaultAsync(x => x.Tenant == tenant && x.RequestId == requestId, ct);
        if (entity is null)
        {
            entity = new AdminAccessRequest { Tenant = tenant, RequestId = requestId };
            db.AdminAccessRequests.Add(entity);
        }

        entity.RequesterUserId =
            Text(p, "requester_user_id", "requester_id", "user_id", "created_by", "owner_user_id")
            ?? envelope.UserId
            ?? entity.RequesterUserId;

        entity.TargetUserId =
            Text(p, "target_user_id", "target_id", "subject_user_id")
            ?? entity.TargetUserId;

        entity.ResourceType = Text(p, "resource_type", "resource", "service") ?? entity.ResourceType;
        entity.Scope = Text(p, "scope", "permission", "permissions") ?? entity.Scope;
        entity.Reason = Text(p, "reason", "message") ?? entity.Reason;

        var rawStatus = Text(p, "status", "state", "decision") ?? StatusFromEvent(envelope.EventType);
        entity.Status = NormalizeAccessRequestStatus(rawStatus);

        entity.RequestedAt = NullableTime(p, "requested_at", "created_at", "submitted_at") ?? entity.RequestedAt;
        if (entity.RequestedAt == default)
        {
            entity.RequestedAt = envelope.Timestamp;
        }

        entity.RequestedBy = Text(p, "requested_by", "created_by", "actor_id") ?? envelope.ActorId ?? entity.RequestedBy;
        entity.ExpiresAt = NullableTime(p, "expires_at", "expires_on") ?? entity.ExpiresAt;

        if (entity.Status is DecisionStatuses.Approved or DecisionStatuses.Rejected)
        {
            entity.ReviewedAt = NullableTime(p, "reviewed_at", "approved_at", "rejected_at", "decided_at") ?? envelope.Timestamp;
            entity.ReviewedBy = Text(p, "reviewed_by", "approved_by", "rejected_by", "decided_by", "actor_id") ?? envelope.ActorId ?? entity.ReviewedBy;
            entity.DecisionReason = Text(p, "decision_reason", "review_reason", "reason") ?? entity.DecisionReason;
        }
    }

    private static async Task UpsertAccessGrantAsync(AdminDbContext db, EventEnvelope envelope, CancellationToken ct)
    {
        var p = envelope.Payload;
        var grantId = Text(p, "grant_id", "access_grant_id", "id") ?? envelope.AggregateId;
        var tenant = envelope.Tenant;
        var entity = await db.AdminAccessGrants.FirstOrDefaultAsync(x => x.Tenant == tenant && x.GrantId == grantId, ct);
        if (entity is null)
        {
            entity = new AdminAccessGrant { Tenant = tenant, GrantId = grantId };
            db.AdminAccessGrants.Add(entity);
        }

        entity.RequestId = Text(p, "request_id", "access_request_id") ?? entity.RequestId;
        entity.RequesterUserId = Text(p, "requester_user_id", "requester_id", "user_id") ?? entity.RequesterUserId;
        entity.TargetUserId = Text(p, "target_user_id", "target_id", "subject_user_id") ?? envelope.UserId ?? entity.TargetUserId;
        entity.ResourceType = Text(p, "resource_type", "resource", "service") ?? entity.ResourceType;
        entity.Scope = Text(p, "scope", "permission", "permissions") ?? entity.Scope;
        entity.Status = NormalizeAccessGrantStatus(Text(p, "status", "state") ?? StatusFromEvent(envelope.EventType));
        entity.ApprovedBy = Text(p, "approved_by", "actor_id") ?? envelope.ActorId ?? entity.ApprovedBy;
        entity.ApprovedAt = NullableTime(p, "approved_at", "created_at") ?? entity.ApprovedAt;
        if (entity.ApprovedAt == default)
        {
            entity.ApprovedAt = envelope.Timestamp;
        }
        entity.ExpiresAt = NullableTime(p, "expires_at", "expires_on") ?? entity.ExpiresAt;
        if (entity.ExpiresAt == default)
        {
            entity.ExpiresAt = DateTimeOffset.UtcNow.AddDays(30);
        }

        if (entity.Status == GrantStatuses.Revoked)
        {
            entity.RevokedBy = Text(p, "revoked_by", "actor_id") ?? envelope.ActorId;
            entity.RevokedAt = NullableTime(p, "revoked_at", "updated_at") ?? envelope.Timestamp;
            entity.RevokeReason = Text(p, "reason", "revoke_reason");
        }
    }

    private static async Task UpsertUserAsync(AdminDbContext db, EventEnvelope envelope, CancellationToken ct)
    {
        var p = envelope.Payload;
        var user = Object(p, "user");
        var tenant = envelope.Tenant;
        var userId = Text(p, "user_id", "id") ?? Text(user, "id", "user_id") ?? envelope.UserId ?? envelope.AggregateId;
        var entity = await db.AdminUserProjections.FirstOrDefaultAsync(x => x.Tenant == tenant && x.UserId == userId, ct);
        if (entity is null)
        {
            entity = new AdminUserProjection { Tenant = tenant, UserId = userId };
            db.AdminUserProjections.Add(entity);
        }
        entity.Username = Text(p, "username") ?? Text(user, "username") ?? entity.Username;
        entity.Email = Text(p, "email") ?? Text(user, "email") ?? entity.Email;
        entity.FullName = Text(p, "full_name", "fullName") ?? Text(user, "full_name", "fullName") ?? entity.FullName;
        entity.Role = Text(p, "role") ?? Text(user, "role") ?? entity.Role;
        entity.AdminStatus = Text(p, "admin_status") ?? Text(user, "admin_status") ?? entity.AdminStatus;
        entity.Status = Text(p, "status") ?? Text(user, "status") ?? StatusFromEvent(envelope.EventType);
        entity.LastSeenAt = NullableTime(p, "last_seen_at") ?? NullableTime(user, "last_login_at", "last_seen_at") ?? entity.LastSeenAt;
        entity.Payload = envelope.Payload.GetRawText();
    }

    private static async Task UpsertCalculationAsync(AdminDbContext db, EventEnvelope envelope, CancellationToken ct)
    {
        var p = envelope.Payload;
        var id = Text(p, "calculation_id", "id") ?? envelope.AggregateId;
        var tenant = envelope.Tenant;
        var entity = await db.AdminCalculationProjections.FirstOrDefaultAsync(x => x.Tenant == tenant && x.CalculationId == id, ct);
        if (entity is null)
        {
            entity = new AdminCalculationProjection { Tenant = tenant, CalculationId = id };
            db.AdminCalculationProjections.Add(entity);
        }
        entity.UserId = envelope.UserId ?? Text(p, "user_id") ?? entity.UserId;
        entity.Status = Text(p, "status") ?? StatusFromEvent(envelope.EventType);
        entity.Operation = Text(p, "operation") ?? entity.Operation;
        entity.OccurredAt = Time(p, "occurred_at", envelope.Timestamp);
        entity.Payload = envelope.Payload.GetRawText();
    }

    private static async Task UpsertTodoAsync(AdminDbContext db, EventEnvelope envelope, CancellationToken ct)
    {
        var p = envelope.Payload;
        var id = Text(p, "todo_id", "id") ?? envelope.AggregateId;
        var tenant = envelope.Tenant;
        var entity = await db.AdminTodoProjections.FirstOrDefaultAsync(x => x.Tenant == tenant && x.TodoId == id, ct);
        if (entity is null)
        {
            entity = new AdminTodoProjection { Tenant = tenant, TodoId = id };
            db.AdminTodoProjections.Add(entity);
        }
        entity.UserId = envelope.UserId ?? Text(p, "user_id") ?? entity.UserId;
        entity.Status = Text(p, "status") ?? StatusFromEvent(envelope.EventType);
        entity.Title = Text(p, "title") ?? entity.Title;
        entity.OccurredAt = Time(p, "occurred_at", envelope.Timestamp);
        entity.Payload = envelope.Payload.GetRawText();
    }

    private static async Task UpsertReportAsync(AdminDbContext db, EventEnvelope envelope, CancellationToken ct)
    {
        var p = envelope.Payload;
        var id = Text(p, "report_id", "id") ?? envelope.AggregateId;
        var tenant = envelope.Tenant;
        var entity = await db.AdminReportProjections.FirstOrDefaultAsync(x => x.Tenant == tenant && x.ReportId == id, ct);
        if (entity is null)
        {
            entity = new AdminReportProjection { Tenant = tenant, ReportId = id };
            db.AdminReportProjections.Add(entity);
        }
        entity.UserId = envelope.UserId ?? Text(p, "user_id", "target_user_id") ?? entity.UserId;
        entity.ReportType = Text(p, "report_type") ?? entity.ReportType;
        entity.Format = Text(p, "format") ?? entity.Format;
        entity.Status = Text(p, "status") ?? StatusFromEvent(envelope.EventType);
        entity.RequestedBy = Text(p, "requested_by") ?? envelope.ActorId ?? entity.RequestedBy;
        entity.RequestedAt = Time(p, "requested_at", envelope.Timestamp);
        entity.Payload = envelope.Payload.GetRawText();
    }

    private static bool IsAccessRequestEvent(EventEnvelope envelope, string topic)
    {
        var eventType = NormalizeEventName(envelope.EventType);
        var aggregateType = NormalizeAggregateName(envelope.AggregateType);

        return topic.Contains("access", StringComparison.OrdinalIgnoreCase) && topic.Contains("request", StringComparison.OrdinalIgnoreCase)
            || aggregateType == "access_request"
            || eventType.StartsWith("access.request.", StringComparison.Ordinal)
            || eventType.StartsWith("user.access.request.", StringComparison.Ordinal)
            || eventType.StartsWith("user.accessrequest.", StringComparison.Ordinal)
            || eventType.StartsWith("accessrequest.", StringComparison.Ordinal);
    }

    private static bool IsAccessGrantEvent(EventEnvelope envelope, string topic)
    {
        var eventType = NormalizeEventName(envelope.EventType);
        var aggregateType = NormalizeAggregateName(envelope.AggregateType);

        return topic.Contains("access", StringComparison.OrdinalIgnoreCase) && topic.Contains("grant", StringComparison.OrdinalIgnoreCase)
            || aggregateType == "access_grant"
            || eventType.StartsWith("access.grant.", StringComparison.Ordinal)
            || eventType.StartsWith("user.access.grant.", StringComparison.Ordinal)
            || eventType.StartsWith("user.accessgrant.", StringComparison.Ordinal)
            || eventType.StartsWith("accessgrant.", StringComparison.Ordinal);
    }

    private static string NormalizeEventName(string eventType)
        => eventType.Replace('-', '.').Replace('_', '.').ToLowerInvariant();

    private static string NormalizeAggregateName(string? aggregateType)
        => (aggregateType ?? string.Empty).Replace('-', '_').Replace('.', '_').ToLowerInvariant();

    private static string NormalizeAccessRequestStatus(string status)
        => status.Replace('-', '_').ToLowerInvariant() switch
        {
            "created" or "requested" or "submitted" or "open" or "pending" => DecisionStatuses.Pending,
            "approved" or "accepted" => DecisionStatuses.Approved,
            "rejected" or "denied" or "declined" => DecisionStatuses.Rejected,
            var value => value
        };

    private static string NormalizeAccessGrantStatus(string status)
        => status.Replace('-', '_').ToLowerInvariant() switch
        {
            "created" or "approved" or "active" or "granted" => GrantStatuses.Active,
            "revoked" or "revoke_requested" => GrantStatuses.Revoked,
            var value => value
        };

    private static string StatusFromEvent(string eventType)
    {
        var normalized = NormalizeEventName(eventType);
        var last = normalized.Split('.', StringSplitOptions.RemoveEmptyEntries).LastOrDefault() ?? "received";
        return last.Replace('-', '_').ToLowerInvariant();
    }

    private static string? Text(JsonElement element, params string[] names)
    {
        foreach (var name in names)
        {
            if (element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var property))
            {
                if (property.ValueKind == JsonValueKind.String) return property.GetString();
                if (property.ValueKind is JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False) return property.ToString();
            }
        }
        return null;
    }

    private static DateTimeOffset Time(JsonElement element, string name, DateTimeOffset fallback) => NullableTime(element, name) ?? fallback;

    private static JsonElement? Object(JsonElement element, string name)
    {
        if (element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.Object)
        {
            return property;
        }
        return null;
    }

    private static string? Text(JsonElement? element, params string[] names)
        => element.HasValue ? Text(element.Value, names) : null;

    private static DateTimeOffset? NullableTime(JsonElement element, params string[] names)
    {
        foreach (var name in names)
        {
            if (element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var property))
            {
                var parsed = JsonValueCoercion.CoerceDate(property);
                if (parsed.HasValue) return parsed.Value.ToUniversalTime();
            }
        }
        return null;
    }

    private static DateTimeOffset? NullableTime(JsonElement? element, params string[] names)
        => element.HasValue ? NullableTime(element.Value, names) : null;

    private static DateOnly? Date(JsonElement element, string name)
    {
        if (element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var property))
        {
            if (property.ValueKind == JsonValueKind.String && DateOnly.TryParse(property.GetString(), out var value)) return value;
        }
        return null;
    }

    private static DateOnly? Date(JsonElement? element, string name)
        => element.HasValue ? Date(element.Value, name) : null;
}
