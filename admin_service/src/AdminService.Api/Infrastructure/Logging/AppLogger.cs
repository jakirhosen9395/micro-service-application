using AdminService.Api.Configuration;
using AdminService.Api.Http;
using System.Net;
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

    public Task ErrorAsync(string evt, string message, Exception exception, HttpContext? http = null, string? errorCode = null, IDictionary<string, object?>? extra = null, CancellationToken cancellationToken = default)
        => LogAsync("ERROR", evt, message, http, exception, errorCode, extra, cancellationToken);

    private async Task LogAsync(string level, string evt, string message, HttpContext? http, Exception? exception, string? errorCode, IDictionary<string, object?>? extra, CancellationToken cancellationToken)
    {
        RequestContext? ctx = http is null ? null : RequestContext.From(http);
        var redactedExtra = extra is null ? new Dictionary<string, object?>() : SecretRedactor.RedactDictionary(extra);
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

        var line = JsonSerializer.Serialize(document, JsonOptionsFactory.Options);
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
}
