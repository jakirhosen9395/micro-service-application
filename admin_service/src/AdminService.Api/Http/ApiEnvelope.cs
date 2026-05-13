using System.Text.Json;

namespace AdminService.Api.Http;

public static class ApiEnvelope
{
    public static IResult Ok(object? data, string message, HttpContext http, int statusCode = StatusCodes.Status200OK)
    {
        var ctx = RequestContext.From(http);
        return Results.Json(new
        {
            status = "ok",
            message,
            data = data ?? new { },
            request_id = ctx.RequestId,
            trace_id = ctx.TraceId,
            timestamp = DateTimeOffset.UtcNow
        }, JsonOptionsFactory.Options, statusCode: statusCode);
    }

    public static IResult Created(object? data, string message, HttpContext http) => Ok(data, message, http, StatusCodes.Status201Created);

    public static IResult Error(string message, string errorCode, HttpContext http, int statusCode, object? details = null)
    {
        return Results.Json(BuildError(message, errorCode, http, details), JsonOptionsFactory.Options, statusCode: statusCode);
    }

    public static IResult NotFound(string message, HttpContext http, object? details = null) => Error(message, "NOT_FOUND", http, StatusCodes.Status404NotFound, details);
    public static IResult Conflict(string message, HttpContext http, object? details = null) => Error(message, "CONFLICT", http, StatusCodes.Status409Conflict, details);
    public static IResult BadRequest(string message, HttpContext http, object? details = null) => Error(message, "BAD_REQUEST", http, StatusCodes.Status400BadRequest, details);
    public static IResult Forbidden(string message, HttpContext http, object? details = null) => Error(message, "FORBIDDEN", http, StatusCodes.Status403Forbidden, details);
    public static IResult Unauthorized(string message, HttpContext http, object? details = null) => Error(message, "UNAUTHORIZED", http, StatusCodes.Status401Unauthorized, details);

    public static async Task WriteErrorAsync(HttpContext http, int statusCode, string errorCode, string message, object? details = null)
    {
        http.Response.StatusCode = statusCode;
        http.Response.ContentType = "application/json; charset=utf-8";
        await JsonSerializer.SerializeAsync(http.Response.Body, BuildError(message, errorCode, http, details), JsonOptionsFactory.Options, http.RequestAborted);
    }

    private static object BuildError(string message, string errorCode, HttpContext http, object? details)
    {
        var ctx = RequestContext.From(http);
        return new
        {
            status = "error",
            message,
            error_code = errorCode,
            details = details ?? new { },
            path = http.Request.Path.Value ?? string.Empty,
            request_id = ctx.RequestId,
            trace_id = ctx.TraceId,
            timestamp = DateTimeOffset.UtcNow
        };
    }
}
