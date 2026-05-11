using AdminService.Api.Infrastructure.Logging;
using System.Diagnostics;

namespace AdminService.Api.Middleware;

public sealed class RequestLoggingMiddleware
{
    private static readonly HashSet<string> SuppressedSuccessPaths = new(StringComparer.OrdinalIgnoreCase)
    {
        "/hello", "/health", "/docs"
    };

    private readonly RequestDelegate _next;
    private readonly AppLogger _logger;

    public RequestLoggingMiddleware(RequestDelegate next, AppLogger logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext http)
    {
        var stopwatch = Stopwatch.StartNew();
        await _next(http);
        stopwatch.Stop();
        http.Items["duration_ms"] = Math.Round(stopwatch.Elapsed.TotalMilliseconds, 3);

        var path = http.Request.Path.Value ?? string.Empty;
        if (http.Response.StatusCode < 400 && SuppressedSuccessPaths.Contains(path)) return;

        var level = http.Response.StatusCode >= 500 ? "ERROR" : http.Response.StatusCode >= 400 ? "WARN" : "INFO";
        var evt = "http.request.completed";
        var extra = new Dictionary<string, object?>
        {
            ["method"] = http.Request.Method,
            ["path"] = path,
            ["status_code"] = http.Response.StatusCode,
            ["duration_ms"] = Math.Round(stopwatch.Elapsed.TotalMilliseconds, 3)
        };

        if (level == "WARN")
        {
            await _logger.WarnAsync(evt, "request completed", http, errorCode: http.Response.StatusCode.ToString(), extra: extra, cancellationToken: CancellationToken.None);
        }
        else if (level == "ERROR")
        {
            await _logger.WarnAsync(evt, "request completed with server error", http, errorCode: http.Response.StatusCode.ToString(), extra: extra, cancellationToken: CancellationToken.None);
        }
        else
        {
            await _logger.InfoAsync(evt, "request completed", http, extra, CancellationToken.None);
        }
    }
}
