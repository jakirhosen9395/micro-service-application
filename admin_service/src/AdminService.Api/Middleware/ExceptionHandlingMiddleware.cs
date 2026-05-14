using AdminService.Api.Http;
using AdminService.Api.Infrastructure.Logging;

namespace AdminService.Api.Middleware;

public sealed class ExceptionHandlingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly AppLogger _logger;

    public ExceptionHandlingMiddleware(RequestDelegate next, AppLogger logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext http)
    {
        try
        {
            await _next(http);
        }
        catch (OperationCanceledException) when (http.RequestAborted.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            if (!http.Response.HasStarted)
            {
                http.Response.StatusCode = StatusCodes.Status500InternalServerError;
            }

            await _logger.ErrorAsync("http.request.failed", "unhandled request failure", ex, http, "INTERNAL_SERVER_ERROR", cancellationToken: CancellationToken.None);
            if (!http.Response.HasStarted)
            {
                await ApiEnvelope.WriteErrorAsync(http, StatusCodes.Status500InternalServerError, "INTERNAL_SERVER_ERROR", "Internal server error");
            }
        }
    }
}
