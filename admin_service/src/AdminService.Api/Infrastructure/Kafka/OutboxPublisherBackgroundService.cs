using AdminService.Api.Configuration;
using AdminService.Api.Domain;
using AdminService.Api.Infrastructure.Logging;
using AdminService.Api.Infrastructure.Observability;
using AdminService.Api.Persistence;
using Confluent.Kafka;
using Elastic.Apm;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using System.Text;
using System.Text.Json;

namespace AdminService.Api.Infrastructure.Kafka;

public sealed class OutboxPublisherBackgroundService : BackgroundService
{
    private const int MaxAttempts = 10;
    private readonly IDbContextFactory<AdminDbContext> _dbFactory;
    private readonly IProducer<string, string> _producer;
    private readonly AppLogger _logger;
    private readonly AdminSettings _settings;
    private readonly DatabaseMigrator _migrator;

    public OutboxPublisherBackgroundService(IDbContextFactory<AdminDbContext> dbFactory, IProducer<string, string> producer, AppLogger logger, AdminSettings settings, DatabaseMigrator migrator)
    {
        _dbFactory = dbFactory;
        _producer = producer;
        _logger = logger;
        _settings = settings;
        _migrator = migrator;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            await _migrator.EnsureCanonicalInfrastructureSchemaAsync(stoppingToken);
        }
        catch (Exception ex)
        {
            await _logger.ErrorAsync("outbox.schema.ensure_failed", "Kafka outbox schema verification failed", ex, errorCode: "OUTBOX_SCHEMA_UNAVAILABLE", cancellationToken: CancellationToken.None);
        }

        await _logger.InfoAsync("outbox.publisher.started", "Kafka outbox publisher started", cancellationToken: stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Agent.Tracer.CaptureTransaction("admin.outbox.publish_batch", "messaging", async transaction =>
                {
                    transaction.SetLabel("component", "outbox");
                    transaction.SetLabel("service", _settings.ServiceName);
                    await PublishBatchAsync(stoppingToken);
                });
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.UndefinedTable)
            {
                await _logger.WarnAsync("outbox.schema.missing", "Kafka outbox table is missing; attempting schema repair", errorCode: "OUTBOX_SCHEMA_MISSING", cancellationToken: CancellationToken.None);
                try
                {
                    await _migrator.EnsureCanonicalInfrastructureSchemaAsync(CancellationToken.None);
                }
                catch (Exception repairException)
                {
                    await _logger.ErrorAsync("outbox.schema.repair_failed", "Kafka outbox schema repair failed", repairException, errorCode: "OUTBOX_SCHEMA_REPAIR_FAILED", cancellationToken: CancellationToken.None);
                }
            }
            catch (Exception ex)
            {
                await _logger.ErrorAsync("outbox.publisher.failed", "Kafka outbox publisher loop failed", ex, errorCode: "OUTBOX_PUBLISHER_FAILED", cancellationToken: CancellationToken.None);
            }

            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
        }
    }

    private async Task PublishBatchAsync(CancellationToken cancellationToken)
    {
        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        var now = DateTimeOffset.UtcNow;
        var rows = await db.OutboxEvents
            .Where(x => (x.Status == OutboxStatuses.Pending || x.Status == OutboxStatuses.Failed) && (x.NextRetryAt == null || x.NextRetryAt <= now))
            .OrderBy(x => x.CreatedAt)
            .Take(25)
            .ToListAsync(cancellationToken);

        Exception? batchFailure = null;
        foreach (var row in rows)
        {
            row.Status = OutboxStatuses.Processing;
            row.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(cancellationToken);

            try
            {
                var key = BuildMessageKey(row);
                var message = new Message<string, string>
                {
                    Key = key,
                    Value = row.Payload,
                    Headers = BuildHeaders(row)
                };
                var span = ApmTelemetry.StartSpan($"Kafka produce {row.Topic}", "messaging", "kafka", "send", new Dictionary<string, object?>
                {
                    ["dependency"] = "kafka",
                    ["messaging_system"] = "kafka",
                    ["messaging_operation"] = "send",
                    ["topic"] = row.Topic,
                    ["event_id"] = row.EventId,
                    ["event_type"] = row.EventType,
                    ["tenant"] = row.Tenant,
                    ["aggregate_type"] = row.AggregateType,
                    ["aggregate_id"] = row.AggregateId,
                    ["attempt_count"] = row.AttemptCount
                });
                try
                {
                    var result = await _producer.ProduceAsync(row.Topic, message, cancellationToken);
                    ApmTelemetry.SetLabel(span, "partition", result.Partition.Value);
                    ApmTelemetry.SetLabel(span, "offset", result.Offset.Value);
                }
                catch (Exception ex)
                {
                    ApmTelemetry.CaptureException(ex);
                    throw;
                }
                finally
                {
                    span?.End();
                }
                row.Status = OutboxStatuses.Sent;
                row.SentAt = DateTimeOffset.UtcNow;
                row.LastError = null;
            }
            catch (Exception ex)
            {
                batchFailure ??= ex;
                row.AttemptCount += 1;
                row.LastError = SecretRedactor.SafeExceptionMessage(ex);
                row.Status = row.AttemptCount >= MaxAttempts ? OutboxStatuses.DeadLettered : OutboxStatuses.Failed;
                row.NextRetryAt = DateTimeOffset.UtcNow.AddSeconds(Math.Min(300, Math.Pow(2, Math.Min(row.AttemptCount, 6))));
                await _logger.ErrorAsync("outbox.publish.failed", "Kafka outbox event publish failed", ex, errorCode: "KAFKA_PUBLISH_FAILED", extra: new Dictionary<string, object?>
                {
                    ["event_id"] = row.EventId,
                    ["event_type"] = row.EventType,
                    ["topic"] = row.Topic,
                    ["attempt_count"] = row.AttemptCount
                }, cancellationToken: cancellationToken);
            }
            finally
            {
                row.UpdatedAt = DateTimeOffset.UtcNow;
                await db.SaveChangesAsync(cancellationToken);
            }
        }

        if (batchFailure is not null) throw batchFailure;
    }

    private static Headers BuildHeaders(OutboxEvent row)
    {
        var headers = new Headers
        {
            { "event_id", Encoding.UTF8.GetBytes(row.EventId) },
            { "event_type", Encoding.UTF8.GetBytes(row.EventType) },
            { "service", Encoding.UTF8.GetBytes("admin_service") },
            { "tenant", Encoding.UTF8.GetBytes(row.Tenant) }
        };
        if (!string.IsNullOrWhiteSpace(row.TraceId)) headers.Add("trace_id", Encoding.UTF8.GetBytes(row.TraceId));
        if (!string.IsNullOrWhiteSpace(row.CorrelationId)) headers.Add("correlation_id", Encoding.UTF8.GetBytes(row.CorrelationId));
        ApmTelemetry.InjectTraceHeaders(headers);
        return headers;
    }

    private static string BuildMessageKey(OutboxEvent row)
    {
        try
        {
            using var document = JsonDocument.Parse(row.Payload);
            if (document.RootElement.TryGetProperty("user_id", out var user) && user.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(user.GetString()))
            {
                return $"{row.Tenant}:{user.GetString()}";
            }
        }
        catch
        {
            // Fall back to aggregate key.
        }
        return $"{row.Tenant}:{row.AggregateId}";
    }
}
