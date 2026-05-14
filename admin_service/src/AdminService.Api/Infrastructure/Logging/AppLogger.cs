using AdminService.Api.Configuration;
using AdminService.Api.Http;
using AdminService.Api.Infrastructure.Observability;
using Elastic.Apm;
using System.Net;
using System.Diagnostics;
using System.Text.Json;

namespace AdminService.Api.Infrastructure.Logging;

public sealed class AppLogger
{
    private readonly AdminSettings _settings;
    private readonly MongoLogWriter? _mongoLogWriter;
    private readonly string _hostName = Dns.GetHostName();

    public AppLogger(AdminSettings settings, MongoLogWriter? mongoLogWriter = null)
    {
        _settings = settings;
        _mongoLogWriter = mongoLogWriter;
    }

    public Task InfoAsync(string evt, string message, HttpContext? http = null, IDictionary<string, object?>? extra = null, CancellationToken cancellationToken = default)
        => LogAsync("INFO", evt, message, http, null, null, extra, cancellationToken);

    public Task WarnAsync(string evt, string message, HttpContext? http = null, string? errorCode = null, IDictionary<string, object?>? extra = null, CancellationToken cancellationToken = default)
        => LogAsync("WARN", evt, message, http, null, errorCode, extra, cancellationToken);

    public Task ErrorAsync(string evt, string message, HttpContext? http = null, string? errorCode = null, IDictionary<string, object?>? extra = null, CancellationToken cancellationToken = default)
        => LogAsync("ERROR", evt, message, http, null, errorCode, extra, cancellationToken);

    public Task ErrorAsync(string evt, string message, Exception exception, HttpContext? http = null, string? errorCode = null, IDictionary<string, object?>? extra = null, CancellationToken cancellationToken = default)
        => LogAsync("ERROR", evt, message, http, exception, errorCode, extra, cancellationToken);

    private async Task LogAsync(string level, string evt, string message, HttpContext? http, Exception? exception, string? errorCode, IDictionary<string, object?>? extra, CancellationToken cancellationToken)
    {
        if (exception is not null)
        {
            ApmTelemetry.CaptureException(exception);
        }
        else if (level == "ERROR")
        {
            ApmTelemetry.CaptureError(message, evt);
        }

        RequestContext? ctx = http is null ? null : RequestContext.From(http);
        var redactedExtra = extra is null ? new Dictionary<string, object?>() : SecretRedactor.RedactDictionary(extra);
        var activity = Activity.Current;
        var currentTransaction = Agent.Tracer.CurrentTransaction;
        var currentSpan = Agent.Tracer.CurrentSpan;
        var elasticTraceId = activity?.TraceId.ToString() ?? StringProperty(currentTransaction, "TraceId") ?? StringProperty(currentSpan, "TraceId");
        var elasticTransactionId = StringProperty(currentTransaction, "Id") ?? activity?.SpanId.ToString();
        var elasticSpanId = StringProperty(currentSpan, "Id") ?? activity?.SpanId.ToString();
        var document = new Dictionary<string, object?>
        {
            ["timestamp"] = DateTimeOffset.UtcNow,
            ["level"] = level,
            ["service"] = _settings.ServiceName,
            ["version"] = _settings.Version,
            ["environment"] = _settings.EnvironmentName,
            ["tenant"] = ctx?.Tenant ?? _settings.Tenant,
            ["logger"] = "app",
            ["event"] = evt,
            ["message"] = message,
            ["request_id"] = ctx?.RequestId,
            ["trace_id"] = ctx?.TraceId,
            ["correlation_id"] = ctx?.CorrelationId,
            ["elastic_trace_id"] = elasticTraceId,
            ["elastic_transaction_id"] = elasticTransactionId,
            ["elastic_span_id"] = elasticSpanId,
            ["user_id"] = ctx?.UserId,
            ["actor_id"] = ctx?.UserId,
            ["method"] = http?.Request.Method,
            ["path"] = http?.Request.Path.Value,
            ["status_code"] = http?.Response.StatusCode,
            ["duration_ms"] = http?.Items.TryGetValue("duration_ms", out var duration) == true ? duration : null,
            ["client_ip"] = ctx?.ClientIp,
            ["user_agent"] = ctx?.UserAgent,
            ["dependency"] = redactedExtra.TryGetValue("dependency", out var dep) ? dep : null,
            ["error_code"] = errorCode,
            ["exception_class"] = exception?.GetType().Name,
            ["exception_message"] = exception is null ? null : SecretRedactor.SafeExceptionMessage(exception),
            ["stack_trace"] = level == "ERROR" && exception is not null ? exception.StackTrace : null,
            ["host"] = _hostName,
            ["extra"] = redactedExtra
        };

        var stdoutDocument = new Dictionary<string, object?>(document)
        {
            ["ecs.version"] = "8.11.0",
            ["log.level"] = level.ToLowerInvariant(),
            ["service.name"] = _settings.ServiceName,
            ["service.version"] = _settings.Version,
            ["service.environment"] = _settings.EnvironmentName,
            ["service.node.name"] = _hostName,
            ["host.name"] = _hostName,
            ["event.dataset"] = $"{_settings.ServiceName}.{document["logger"]}",
            ["event.action"] = evt,
            ["event.kind"] = level == "ERROR" ? "error" : "event",
            ["event.outcome"] = level == "INFO" ? "success" : "failure",
            ["trace.id"] = elasticTraceId,
            ["transaction.id"] = elasticTransactionId,
            ["span.id"] = elasticSpanId,
            ["http.request.method"] = http?.Request.Method,
            ["url.path"] = http?.Request.Path.Value,
            ["http.response.status_code"] = http?.Response.StatusCode,
            ["client.ip"] = ctx?.ClientIp,
            ["user.id"] = ctx?.UserId,
            ["user_agent.original"] = ctx?.UserAgent,
            ["error.type"] = exception?.GetType().FullName,
            ["error.message"] = exception is null ? null : SecretRedactor.SafeExceptionMessage(exception),
            ["error.stack_trace"] = level == "ERROR" && exception is not null ? exception.StackTrace : null
        };

        var line = JsonSerializer.Serialize(stdoutDocument, JsonOptionsFactory.Options);
        Console.WriteLine(line);

        if (_mongoLogWriter is not null)
        {
            try
            {
                await _mongoLogWriter.WriteAsync(document, cancellationToken);
            }
            catch (Exception writeException)
            {
                var fallback = new Dictionary<string, object?>
                {
                    ["timestamp"] = DateTimeOffset.UtcNow,
                    ["level"] = "WARN",
                    ["service"] = _settings.ServiceName,
                    ["event"] = "mongodb.log_write_failed",
                    ["message"] = SecretRedactor.SafeExceptionMessage(writeException)
                };
                Console.WriteLine(JsonSerializer.Serialize(fallback, JsonOptionsFactory.Options));
            }
        }
    }

    private static string? StringProperty(object? source, string propertyName)
    {
        try
        {
            return source?.GetType().GetProperty(propertyName)?.GetValue(source)?.ToString();
        }
        catch
        {
            return null;
        }
    }
}
