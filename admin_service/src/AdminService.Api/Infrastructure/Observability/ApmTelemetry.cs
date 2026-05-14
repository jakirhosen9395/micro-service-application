using AdminService.Api.Configuration;
using AdminService.Api.Http;
using Elastic.Apm;
using Elastic.Apm.Api;
using Microsoft.Extensions.Logging;
using System.Diagnostics;
using System.Globalization;
using System.Text;

namespace AdminService.Api.Infrastructure.Observability;

public static class ApmTelemetry
{
    private const string CaptureMarker = "elastic_apm_captured";

    public static void ConfigureElasticEnvironment(AdminSettings settings)
    {
        Environment.SetEnvironmentVariable("ELASTIC_APM_ENABLED", "true");
        Environment.SetEnvironmentVariable("ELASTIC_APM_RECORDING", "true");
        Environment.SetEnvironmentVariable("ELASTIC_APM_SERVICE_NAME", settings.ServiceName);
        Environment.SetEnvironmentVariable("ELASTIC_APM_SERVICE_VERSION", settings.Version.TrimStart('v', 'V'));
        Environment.SetEnvironmentVariable("ELASTIC_APM_ENVIRONMENT", settings.EnvironmentName);
        Environment.SetEnvironmentVariable("ELASTIC_APM_SERVER_URL", settings.ApmServerUrl);
        Environment.SetEnvironmentVariable("ELASTIC_APM_SERVER_URLS", settings.ApmServerUrl);
        Environment.SetEnvironmentVariable("ELASTIC_APM_SECRET_TOKEN", settings.ApmSecretToken);
        Environment.SetEnvironmentVariable("ELASTIC_APM_TRANSACTION_SAMPLE_RATE", settings.ApmTransactionSampleRate.ToString(CultureInfo.InvariantCulture));
        Environment.SetEnvironmentVariable("ELASTIC_APM_CAPTURE_BODY", settings.ApmCaptureBody);
        Environment.SetEnvironmentVariable("ELASTIC_APM_CAPTURE_BODY_CONTENT_TYPES", "application/json*,application/x-www-form-urlencoded*");
        Environment.SetEnvironmentVariable("ELASTIC_APM_CAPTURE_HEADERS", "true");
        Environment.SetEnvironmentVariable("ELASTIC_APM_SANITIZE_FIELD_NAMES", "password,passwd,pwd,secret,*key,*token*,*session*,*credit*,*card*,*auth*,authorization,set-cookie,cookie,admin_jwt_secret,admin_apm_secret_token");
        Environment.SetEnvironmentVariable("ELASTIC_APM_CENTRAL_CONFIG", "true");
        Environment.SetEnvironmentVariable("ELASTIC_APM_METRICS_INTERVAL", "30s");
        Environment.SetEnvironmentVariable("ELASTIC_APM_TRANSACTION_MAX_SPANS", "1000");
        Environment.SetEnvironmentVariable("ELASTIC_APM_SPAN_COMPRESSION_ENABLED", "false");
        Environment.SetEnvironmentVariable("ELASTIC_APM_STACK_TRACE_LIMIT", "50");
        Environment.SetEnvironmentVariable("ELASTIC_APM_SPAN_FRAMES_MIN_DURATION", "0ms");
        Environment.SetEnvironmentVariable("ELASTIC_APM_USE_ELASTIC_TRACEPARENT_HEADER", "true");
        Environment.SetEnvironmentVariable("ELASTIC_APM_LOG_LEVEL", ElasticLogLevel(settings.LogLevel));
        Environment.SetEnvironmentVariable("ELASTIC_APM_GLOBAL_LABELS", $"tenant={settings.Tenant},service={settings.ServiceName},environment={settings.EnvironmentName}");
    }

    public static LogLevel ParseLogLevel(string level)
    {
        return level.Trim().ToLowerInvariant() switch
        {
            "trace" => LogLevel.Trace,
            "debug" => LogLevel.Debug,
            "warning" or "warn" => LogLevel.Warning,
            "error" => LogLevel.Error,
            "critical" or "fatal" => LogLevel.Critical,
            "none" => LogLevel.None,
            _ => LogLevel.Information
        };
    }

    public static void EnrichHttpTransaction(HttpContext http, AdminSettings settings)
    {
        var transaction = Agent.Tracer.CurrentTransaction;
        if (transaction is null) return;

        var ctx = RequestContext.From(http);
        var route = http.Request.Path.Value ?? string.Empty;
        var userId = string.IsNullOrWhiteSpace(ctx.UserId) ? null : ctx.UserId;

        SetLabel(transaction, "service_name", settings.ServiceName);
        SetLabel(transaction, "service_version", settings.Version);
        SetLabel(transaction, "environment", settings.EnvironmentName);
        SetLabel(transaction, "tenant", string.IsNullOrWhiteSpace(ctx.Tenant) ? settings.Tenant : ctx.Tenant);
        SetLabel(transaction, "request_id", ctx.RequestId);
        SetLabel(transaction, "trace_id", ctx.TraceId);
        SetLabel(transaction, "correlation_id", ctx.CorrelationId);
        SetLabel(transaction, "user_id", userId);
        SetLabel(transaction, "client_ip", ctx.ClientIp);
        SetLabel(transaction, "user_agent", ctx.UserAgent);
        SetLabel(transaction, "http_method", http.Request.Method);
        SetLabel(transaction, "http_path", route);
        SetLabel(transaction, "http_route", http.GetEndpoint()?.DisplayName ?? route);
        SetLabel(transaction, "http_status_code", http.Response.StatusCode);

        if (http.Items.TryGetValue("duration_ms", out var durationMs))
        {
            SetLabel(transaction, "duration_ms", durationMs);
        }
    }

    public static ISpan? StartSpan(string name, string type, string subtype, string action, IDictionary<string, object?>? labels = null)
    {
        var span = Agent.Tracer.CurrentSpan?.StartSpan(name, type, subtype, action)
            ?? Agent.Tracer.CurrentTransaction?.StartSpan(name, type, subtype, action);
        ApplyLabels(span, labels);
        return span;
    }

    public static async Task CaptureSpanAsync(string name, string type, string subtype, string action, Func<Task> operation, IDictionary<string, object?>? labels = null)
    {
        var span = StartSpan(name, type, subtype, action, labels);
        try
        {
            await operation();
            SetLabel(span, "outcome", "success");
        }
        catch (Exception ex)
        {
            if (span is not null)
            {
                span.CaptureException(ex);
                MarkCaptured(ex);
            }
            else CaptureException(ex);
            SetLabel(span, "outcome", "failure");
            throw;
        }
        finally
        {
            span?.End();
        }
    }

    public static async Task<T> CaptureSpanAsync<T>(string name, string type, string subtype, string action, Func<Task<T>> operation, IDictionary<string, object?>? labels = null)
    {
        var span = StartSpan(name, type, subtype, action, labels);
        try
        {
            var result = await operation();
            SetLabel(span, "outcome", "success");
            return result;
        }
        catch (Exception ex)
        {
            if (span is not null)
            {
                span.CaptureException(ex);
                MarkCaptured(ex);
            }
            else CaptureException(ex);
            SetLabel(span, "outcome", "failure");
            throw;
        }
        finally
        {
            span?.End();
        }
    }

    public static void CaptureSpan(string name, string type, string subtype, string action, Action operation, IDictionary<string, object?>? labels = null)
    {
        var span = StartSpan(name, type, subtype, action, labels);
        try
        {
            operation();
            SetLabel(span, "outcome", "success");
        }
        catch (Exception ex)
        {
            if (span is not null)
            {
                span.CaptureException(ex);
                MarkCaptured(ex);
            }
            else CaptureException(ex);
            SetLabel(span, "outcome", "failure");
            throw;
        }
        finally
        {
            span?.End();
        }
    }

    public static void CaptureException(Exception exception)
    {
        if (exception.Data.Contains(CaptureMarker)) return;

        var currentSpan = Agent.Tracer.CurrentSpan;
        if (currentSpan is not null)
        {
            currentSpan.CaptureException(exception);
            MarkCaptured(exception);
            return;
        }

        var currentTransaction = Agent.Tracer.CurrentTransaction;
        if (currentTransaction is not null)
        {
            currentTransaction.CaptureException(exception);
            MarkCaptured(exception);
            return;
        }

        Agent.Tracer.CaptureException(exception);
        MarkCaptured(exception);
    }

    public static void CaptureError(string message, string culprit)
    {
        Agent.Tracer.CaptureError(message, culprit);
    }

    public static void SetLabel(ISpan? span, string key, object? value)
    {
        if (span is null || string.IsNullOrWhiteSpace(key) || value is null) return;
        switch (value)
        {
            case string text when !string.IsNullOrWhiteSpace(text):
                span.SetLabel(key, text);
                break;
            case bool boolean:
                span.SetLabel(key, boolean);
                break;
            case int integer:
                span.SetLabel(key, integer);
                break;
            case long integer:
                span.SetLabel(key, integer);
                break;
            case float number:
                span.SetLabel(key, number);
                break;
            case double number:
                span.SetLabel(key, number);
                break;
            case decimal number:
                span.SetLabel(key, decimal.ToDouble(number));
                break;
            default:
                var text = value.ToString();
                if (!string.IsNullOrWhiteSpace(text)) span.SetLabel(key, text);
                break;
        }
    }

    public static void SetLabel(ITransaction? transaction, string key, object? value)
    {
        if (transaction is null || string.IsNullOrWhiteSpace(key) || value is null) return;
        switch (value)
        {
            case string text when !string.IsNullOrWhiteSpace(text):
                transaction.SetLabel(key, text);
                break;
            case bool boolean:
                transaction.SetLabel(key, boolean);
                break;
            case int integer:
                transaction.SetLabel(key, integer);
                break;
            case long integer:
                transaction.SetLabel(key, integer);
                break;
            case float number:
                transaction.SetLabel(key, number);
                break;
            case double number:
                transaction.SetLabel(key, number);
                break;
            case decimal number:
                transaction.SetLabel(key, decimal.ToDouble(number));
                break;
            default:
                var text = value.ToString();
                if (!string.IsNullOrWhiteSpace(text)) transaction.SetLabel(key, text);
                break;
        }
    }

    public static void InjectTraceHeaders(Confluent.Kafka.Headers headers)
    {
        var activity = Activity.Current;
        if (!string.IsNullOrWhiteSpace(activity?.Id))
        {
            headers.Add("traceparent", Encoding.UTF8.GetBytes(activity.Id));
        }

        if (!string.IsNullOrWhiteSpace(activity?.TraceStateString))
        {
            headers.Add("tracestate", Encoding.UTF8.GetBytes(activity.TraceStateString));
        }
    }

    private static void ApplyLabels(ISpan? span, IDictionary<string, object?>? labels)
    {
        if (labels is null) return;
        foreach (var (key, value) in labels)
        {
            SetLabel(span, key, value);
        }
    }

    private static string ElasticLogLevel(string level)
    {
        return ParseLogLevel(level) switch
        {
            LogLevel.Trace => "Trace",
            LogLevel.Debug => "Debug",
            LogLevel.Warning => "Warning",
            LogLevel.Error => "Error",
            LogLevel.Critical => "Critical",
            _ => "Information"
        };
    }

    private static void MarkCaptured(Exception exception)
    {
        if (!exception.Data.Contains(CaptureMarker))
        {
            exception.Data[CaptureMarker] = true;
        }
    }
}
