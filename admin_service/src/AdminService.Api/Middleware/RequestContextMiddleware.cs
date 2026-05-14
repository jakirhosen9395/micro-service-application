using AdminService.Api.Configuration;
using AdminService.Api.Http;
using AdminService.Api.Infrastructure.Observability;
using AdminService.Api.Security;
using System.Diagnostics;

namespace AdminService.Api.Middleware;

public sealed class RequestContextMiddleware
{
    private readonly RequestDelegate _next;
    private readonly AdminSettings _settings;

    public RequestContextMiddleware(RequestDelegate next, AdminSettings settings)
    {
        _next = next;
        _settings = settings;
    }

    public async Task InvokeAsync(HttpContext http)
    {
        if (_settings.SecurityRequireHttps && !IsHttps(http))
        {
            http.Response.StatusCode = StatusCodes.Status400BadRequest;
            await ApiEnvelope.WriteErrorAsync(http, StatusCodes.Status400BadRequest, "HTTPS_REQUIRED", "HTTPS is required");
            return;
        }

        var requestId = HeaderOrNew(http, "X-Request-ID");
        var traceId = http.Request.Headers.TryGetValue("X-Trace-ID", out var traceHeader) && !string.IsNullOrWhiteSpace(traceHeader)
            ? traceHeader.ToString()
            : Activity.Current?.TraceId.ToString() ?? requestId;
        var correlationId = http.Request.Headers.TryGetValue("X-Correlation-ID", out var corrHeader) && !string.IsNullOrWhiteSpace(corrHeader)
            ? corrHeader.ToString()
            : requestId;

        var userId = AdminClaims.Get(http.User, "sub", "user_id", ClaimNames.NameIdentifier);
        var tenant = AdminClaims.Get(http.User, "tenant") ?? _settings.Tenant;
        var ctx = new RequestContext(
            requestId,
            traceId,
            correlationId,
            tenant,
            userId,
            http.Connection.RemoteIpAddress?.ToString(),
            http.Request.Headers.UserAgent.ToString());

        http.Items[nameof(RequestContext)] = ctx;
        http.Response.Headers["X-Request-ID"] = requestId;
        http.Response.Headers["X-Trace-ID"] = traceId;
        http.Response.Headers["X-Correlation-ID"] = correlationId;
        ApmTelemetry.EnrichHttpTransaction(http, _settings);
        await _next(http);
    }

    private static string HeaderOrNew(HttpContext http, string name)
    {
        return http.Request.Headers.TryGetValue(name, out var value) && !string.IsNullOrWhiteSpace(value)
            ? value.ToString()
            : $"req-{Guid.NewGuid():N}";
    }

    private static bool IsHttps(HttpContext http)
    {
        if (http.Request.IsHttps) return true;
        return http.Request.Headers.TryGetValue("X-Forwarded-Proto", out var proto) && proto.ToString().Equals("https", StringComparison.OrdinalIgnoreCase);
    }
}
