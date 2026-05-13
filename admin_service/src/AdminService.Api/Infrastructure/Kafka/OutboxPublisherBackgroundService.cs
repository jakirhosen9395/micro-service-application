using AdminService.Api.Configuration;
using AdminService.Api.Domain;
using AdminService.Api.Infrastructure.Logging;
using AdminService.Api.Persistence;
using Confluent.Kafka;
using Elastic.Apm;
using Microsoft.EntityFrameworkCore;
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

    public OutboxPublisherBackgroundService(IDbContextFactory<AdminDbContext> dbFactory, IProducer<string, string> producer, AppLogger logger, AdminSettings settings)
    {
        _dbFactory = dbFactory;
        _producer = producer;
        _logger = logger;
        _settings = settings;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
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
                var span = Agent.Tracer.CurrentTransaction?.StartSpan($"Kafka produce {row.Topic}", "messaging", "kafka", "send");
                try
                {
                    await _producer.ProduceAsync(row.Topic, message, cancellationToken);
                }
                catch (Exception ex)
                {
                    span?.CaptureException(ex);
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
