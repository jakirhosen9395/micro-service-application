using AdminService.Api.Configuration;
using AdminService.Api.Contracts;
using AdminService.Api.Domain;
using AdminService.Api.Http;
using AdminService.Api.Infrastructure.Logging;
using AdminService.Api.Infrastructure.Storage;
using AdminService.Api.Persistence;
using AdminService.Api.Security;
using System.Text.Json;

namespace AdminService.Api.Infrastructure.Audit;

public sealed class AuditService
{
    private readonly AdminSettings _settings;
    private readonly S3AuditWriter _s3;
    private readonly AppLogger _logger;

    public AuditService(AdminSettings settings, S3AuditWriter s3, AppLogger logger)
    {
        _settings = settings;
        _s3 = s3;
        _logger = logger;
    }

    public async Task<string> RecordAsync(
        AdminDbContext db,
        HttpContext http,
        AdminActor actor,
        string eventType,
        string topic,
        string aggregateType,
        string aggregateId,
        string? targetUserId,
        object payload,
        CancellationToken cancellationToken)
    {
        var ctx = RequestContext.From(http);
        var eventId = $"evt-{Guid.NewGuid():N}";
        var payloadElement = ToJsonElement(payload);
        var auditBody = new
        {
            event_id = eventId,
            event_type = eventType,
            service = _settings.ServiceName,
            environment = _settings.EnvironmentName,
            tenant = actor.Tenant,
            user_id = targetUserId,
            actor_id = actor.UserId,
            target_user_id = targetUserId,
            aggregate_type = aggregateType,
            aggregate_id = aggregateId,
            request_id = ctx.RequestId,
            trace_id = ctx.TraceId,
            correlation_id = ctx.CorrelationId,
            client_ip = ctx.ClientIp,
            user_agent = ctx.UserAgent,
            timestamp = DateTimeOffset.UtcNow,
            payload = payloadElement
        };

        string? s3Key = null;
        try
        {
            s3Key = await _s3.WriteAsync(eventType, eventId, actor.UserId, auditBody, cancellationToken);
        }
        catch (Exception ex)
        {
            await _logger.ErrorAsync("s3.audit.write_failed", "S3 audit snapshot write failed", ex, http, "S3_AUDIT_WRITE_FAILED", cancellationToken: cancellationToken);
        }

        db.AdminAuditEvents.Add(new AdminAuditEvent
        {
            EventId = eventId,
            Tenant = actor.Tenant,
            AdminUserId = actor.UserId,
            TargetUserId = targetUserId,
            EventType = eventType,
            ResourceType = aggregateType,
            ResourceId = aggregateId,
            RequestId = ctx.RequestId,
            TraceId = ctx.TraceId,
            CorrelationId = ctx.CorrelationId,
            ClientIp = ctx.ClientIp,
            UserAgent = ctx.UserAgent,
            Payload = JsonSerializer.Serialize(payloadElement, JsonOptionsFactory.Options),
            S3ObjectKey = s3Key,
            CreatedAt = DateTimeOffset.UtcNow
        });

        var envelope = new EventEnvelope
        {
            EventId = eventId,
            EventType = eventType,
            EventVersion = "1.0",
            Service = _settings.ServiceName,
            Environment = _settings.EnvironmentName,
            Tenant = actor.Tenant,
            Timestamp = DateTimeOffset.UtcNow,
            RequestId = ctx.RequestId,
            TraceId = ctx.TraceId,
            CorrelationId = ctx.CorrelationId,
            UserId = targetUserId,
            ActorId = actor.UserId,
            AggregateType = aggregateType,
            AggregateId = aggregateId,
            Payload = payloadElement
        };

        db.OutboxEvents.Add(new OutboxEvent
        {
            EventId = eventId,
            Tenant = actor.Tenant,
            AggregateType = aggregateType,
            AggregateId = aggregateId,
            EventType = eventType,
            EventVersion = "1.0",
            Topic = topic,
            Payload = JsonSerializer.Serialize(envelope, JsonOptionsFactory.Options),
            Status = OutboxStatuses.Pending,
            RequestId = ctx.RequestId,
            TraceId = ctx.TraceId,
            CorrelationId = ctx.CorrelationId,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        });

        return eventId;
    }

    private static JsonElement ToJsonElement(object payload)
    {
        var json = JsonSerializer.Serialize(payload, JsonOptionsFactory.Options);
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.Clone();
    }
}
