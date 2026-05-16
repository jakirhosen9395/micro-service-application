using AdminService.Api.Configuration;
using AdminService.Api.Http;
using Elastic.Apm;
using Elastic.Apm.Api;
using Microsoft.Extensions.Logging;
using System.Collections.Concurrent;
using System.Reflection;
using System.Diagnostics;
using System.Globalization;
using System.Text;

namespace AdminService.Api.Infrastructure.Observability;

public static class ApmTelemetry
{
    private const string CaptureMarker = "elastic_apm_captured";
    private static readonly ActivitySource DependencyActivitySource = new("admin_service.dependencies");
    private static readonly ConcurrentDictionary<ISpan, Activity> SpanActivities = new();

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
        Environment.SetEnvironmentVariable("ELASTIC_APM_OPENTELEMETRY_BRIDGE_ENABLED", "true");
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
        TryConfigureNativeDependencyContext(span, type, subtype, action, labels);

        var activity = StartDependencyActivity(name, type, subtype, action, labels);
        if (span is not null && activity is not null)
        {
            SpanActivities[span] = activity;
        }

        return span;
    }

    public static void EndSpan(ISpan? span)
    {
        if (span is not null && SpanActivities.TryRemove(span, out var activity))
        {
            activity.Stop();
            activity.Dispose();
        }

        span?.End();
    }

    public static async Task CaptureSpanAsync(string name, string type, string subtype, string action, Func<Task> operation, IDictionary<string, object?>? labels = null)
    {
        var span = StartSpan(name, type, subtype, action, labels);
        try
        {
            await operation();
            SetLabel(span, "outcome", "success");
            SetActivityStatus(span, ActivityStatusCode.Ok);
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
            SetActivityStatus(span, ActivityStatusCode.Error, ex.Message);
            throw;
        }
        finally
        {
            EndSpan(span);
        }
    }

    public static async Task<T> CaptureSpanAsync<T>(string name, string type, string subtype, string action, Func<Task<T>> operation, IDictionary<string, object?>? labels = null)
    {
        var span = StartSpan(name, type, subtype, action, labels);
        try
        {
            var result = await operation();
            SetLabel(span, "outcome", "success");
            SetActivityStatus(span, ActivityStatusCode.Ok);
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
            SetActivityStatus(span, ActivityStatusCode.Error, ex.Message);
            throw;
        }
        finally
        {
            EndSpan(span);
        }
    }

    public static void CaptureSpan(string name, string type, string subtype, string action, Action operation, IDictionary<string, object?>? labels = null)
    {
        var span = StartSpan(name, type, subtype, action, labels);
        try
        {
            operation();
            SetLabel(span, "outcome", "success");
            SetActivityStatus(span, ActivityStatusCode.Ok);
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
            SetActivityStatus(span, ActivityStatusCode.Error, ex.Message);
            throw;
        }
        finally
        {
            EndSpan(span);
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
            case string labelString when !string.IsNullOrWhiteSpace(labelString): span.SetLabel(key, labelString); break;
            case bool boolean: span.SetLabel(key, boolean); break;
            case int integer: span.SetLabel(key, integer); break;
            case long integer: span.SetLabel(key, integer); break;
            case float number: span.SetLabel(key, number); break;
            case double number: span.SetLabel(key, number); break;
            case decimal number: span.SetLabel(key, decimal.ToDouble(number)); break;
            default:
                var labelText = value.ToString();
                if (!string.IsNullOrWhiteSpace(labelText)) span.SetLabel(key, labelText);
                break;
        }
    }

    public static void SetLabel(ITransaction? transaction, string key, object? value)
    {
        if (transaction is null || string.IsNullOrWhiteSpace(key) || value is null) return;
        switch (value)
        {
            case string labelString when !string.IsNullOrWhiteSpace(labelString): transaction.SetLabel(key, labelString); break;
            case bool boolean: transaction.SetLabel(key, boolean); break;
            case int integer: transaction.SetLabel(key, integer); break;
            case long integer: transaction.SetLabel(key, integer); break;
            case float number: transaction.SetLabel(key, number); break;
            case double number: transaction.SetLabel(key, number); break;
            case decimal number: transaction.SetLabel(key, decimal.ToDouble(number)); break;
            default:
                var labelText = value.ToString();
                if (!string.IsNullOrWhiteSpace(labelText)) transaction.SetLabel(key, labelText);
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


    private static void TryConfigureNativeDependencyContext(ISpan? span, string type, string subtype, string action, IDictionary<string, object?>? labels)
    {
        if (span is null || !IsDependencyType(type, subtype, labels)) return;

        try
        {
            var resource = DependencyResource(type, subtype, labels);
            SetNestedProperty(span, new[] { "Context", "Destination", "Service", "Resource" }, resource);
            SetNestedProperty(span, new[] { "Context", "Destination", "Service", "Type" }, subtype);
            SetNestedProperty(span, new[] { "Context", "Service", "Target", "Type" }, subtype);
            SetNestedProperty(span, new[] { "Context", "Service", "Target", "Name" }, resource);

            if (type == "db")
            {
                SetNestedProperty(span, new[] { "Context", "Db", "Type" }, NormalizeDbSystem(subtype));
                SetNestedProperty(span, new[] { "Context", "Db", "Instance" }, GetLabel(labels, "db_name")?.ToString());
                SetNestedProperty(span, new[] { "Context", "Db", "Statement" }, GetLabel(labels, "db_statement")?.ToString());
                SetNestedProperty(span, new[] { "Context", "Db", "User" }, GetLabel(labels, "db_user")?.ToString());
            }
        }
        catch
        {
            // Dependency context fields are best-effort because Elastic APM internal
            // model shapes vary by agent version. Normal custom spans and OTel
            // activities are still emitted even if reflection cannot set a field.
        }
    }

    private static void SetNestedProperty(object root, IReadOnlyList<string> path, object? value)
    {
        if (value is null) return;

        object? current = root;
        for (var i = 0; i < path.Count - 1; i++)
        {
            current = GetPropertyValue(current, path[i]);
            if (current is null) return;
        }

        if (current is null) return;
        var propertyName = path[^1];
        var property = current.GetType().GetProperty(propertyName, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        if (property is null || !property.CanWrite) return;

        if (property.PropertyType == typeof(string))
        {
            property.SetValue(current, value.ToString());
            return;
        }

        if (property.PropertyType.IsAssignableFrom(value.GetType()))
        {
            property.SetValue(current, value);
        }
    }

    private static object? GetPropertyValue(object? instance, string propertyName)
    {
        if (instance is null) return null;
        var property = instance.GetType().GetProperty(propertyName, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        return property?.GetValue(instance);
    }

    private static Activity? StartDependencyActivity(string name, string type, string subtype, string action, IDictionary<string, object?>? labels)
    {
        if (!IsDependencyType(type, subtype, labels)) return null;

        var activity = DependencyActivitySource.StartActivity(name, ActivityKind.Client);
        if (activity is null) return null;

        activity.SetTag("elastic.apm.custom_dependency", true);
        activity.SetTag("span.type", type);
        activity.SetTag("span.subtype", subtype);
        activity.SetTag("span.action", action);
        activity.SetTag("dependency", GetLabel(labels, "dependency") ?? subtype);
        activity.SetTag("peer.service", DependencyResource(type, subtype, labels));

        switch (type)
        {
            case "db":
                activity.SetTag("db.system", NormalizeDbSystem(subtype));
                activity.SetTag("db.operation", GetLabel(labels, "db_operation") ?? action);
                SetTagIfPresent(activity, "db.name", GetLabel(labels, "db_name"));
                SetTagIfPresent(activity, "db.collection.name", GetLabel(labels, "db_collection"));
                SetTagIfPresent(activity, "db.namespace", GetLabel(labels, "table"));
                break;
            case "cache":
                activity.SetTag("db.system", subtype);
                activity.SetTag("db.operation", GetLabel(labels, "redis_operation") ?? action);
                activity.SetTag("cache.system", subtype);
                SetTagIfPresent(activity, "db.redis.database_index", GetLabel(labels, "redis_database"));
                break;
            case "messaging":
                activity.SetTag("messaging.system", subtype);
                activity.SetTag("messaging.operation", GetLabel(labels, "messaging_operation") ?? action);
                activity.SetTag("messaging.destination.kind", "topic");
                SetTagIfPresent(activity, "messaging.destination.name", GetLabel(labels, "topic"));
                SetTagIfPresent(activity, "messaging.kafka.consumer.group", GetLabel(labels, "consumer_group"));
                SetTagIfPresent(activity, "messaging.kafka.partition", GetLabel(labels, "partition"));
                SetTagIfPresent(activity, "messaging.kafka.message.offset", GetLabel(labels, "offset"));
                break;
            case "storage":
                activity.SetTag("cloud.provider", "aws");
                activity.SetTag("cloud.service.name", subtype);
                activity.SetTag("rpc.system", "aws-api");
                activity.SetTag("rpc.service", subtype);
                activity.SetTag("rpc.method", action);
                SetTagIfPresent(activity, "aws.s3.bucket", GetLabel(labels, "s3_bucket"));
                break;
            case "external":
                activity.SetTag("http.request.method", "GET");
                activity.SetTag("url.full", GetLabel(labels, "url") ?? subtype);
                break;
        }

        if (labels is not null)
        {
            foreach (var (key, value) in labels)
            {
                SetTagIfPresent(activity, key, value);
            }
        }

        return activity;
    }

    private static bool IsDependencyType(string type, string subtype, IDictionary<string, object?>? labels)
    {
        if (type is "db" or "cache" or "messaging" or "storage" or "external") return true;
        var dependency = GetLabel(labels, "dependency")?.ToString();
        return !string.IsNullOrWhiteSpace(dependency) && dependency is not "jwt";
    }

    private static string DependencyResource(string type, string subtype, IDictionary<string, object?>? labels)
    {
        var dependency = GetLabel(labels, "dependency")?.ToString();
        var topic = GetLabel(labels, "topic")?.ToString();
        var dbName = GetLabel(labels, "db_name")?.ToString();
        return type switch
        {
            "messaging" when !string.IsNullOrWhiteSpace(topic) => $"kafka/{topic}",
            "db" when !string.IsNullOrWhiteSpace(dbName) => $"{NormalizeDbSystem(subtype)}/{dbName}",
            "cache" => "redis",
            "storage" => "s3",
            "external" => dependency ?? subtype,
            _ => dependency ?? subtype
        };
    }

    private static string NormalizeDbSystem(string subtype)
    {
        return subtype switch
        {
            "postgres" => "postgresql",
            "postgresql" => "postgresql",
            "mongodb" => "mongodb",
            _ => subtype
        };
    }

    private static object? GetLabel(IDictionary<string, object?>? labels, string key)
    {
        if (labels is null) return null;
        return labels.TryGetValue(key, out var value) ? value : null;
    }

    private static void SetTagIfPresent(Activity activity, string key, object? value)
    {
        if (value is null || string.IsNullOrWhiteSpace(key)) return;
        switch (value)
        {
            case string tagString when !string.IsNullOrWhiteSpace(tagString): activity.SetTag(key, tagString); break;
            case bool boolean: activity.SetTag(key, boolean); break;
            case int integer: activity.SetTag(key, integer); break;
            case long integer: activity.SetTag(key, integer); break;
            case float number: activity.SetTag(key, number); break;
            case double number: activity.SetTag(key, number); break;
            case decimal number: activity.SetTag(key, decimal.ToDouble(number)); break;
            default:
                var tagText = value.ToString();
                if (!string.IsNullOrWhiteSpace(tagText)) activity.SetTag(key, tagText);
                break;
        }
    }

    private static void SetActivityStatus(ISpan? span, ActivityStatusCode status, string? description = null)
    {
        if (span is null) return;
        if (SpanActivities.TryGetValue(span, out var activity))
        {
            activity.SetStatus(status, description);
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
