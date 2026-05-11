using System.Security.Claims;

namespace AdminService.Api.Http;

public sealed record RequestContext(
    string RequestId,
    string TraceId,
    string CorrelationId,
    string Tenant,
    string? UserId,
    string? ClientIp,
    string? UserAgent)
{
    public static RequestContext From(HttpContext http)
    {
        var userId = Claim(http.User, "sub") ?? Claim(http.User, "user_id") ?? Claim(http.User, ClaimTypes.NameIdentifier);
        var tenant = Claim(http.User, "tenant");
        if (http.Items.TryGetValue(nameof(RequestContext), out var value) && value is RequestContext context)
        {
            return context with
            {
                UserId = context.UserId ?? userId,
                Tenant = string.IsNullOrWhiteSpace(context.Tenant) ? tenant ?? string.Empty : context.Tenant
            };
        }

        return new RequestContext(
            http.TraceIdentifier,
            http.TraceIdentifier,
            http.TraceIdentifier,
            tenant ?? string.Empty,
            userId,
            http.Connection.RemoteIpAddress?.ToString(),
            http.Request.Headers.UserAgent.ToString());
    }

    private static string? Claim(ClaimsPrincipal principal, string type)
    {
        return principal.Claims.FirstOrDefault(c => string.Equals(c.Type, type, StringComparison.OrdinalIgnoreCase))?.Value;
    }
}
