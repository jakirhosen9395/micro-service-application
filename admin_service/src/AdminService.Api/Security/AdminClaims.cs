using System.Security.Claims;

namespace AdminService.Api.Security;

public static class ClaimNames
{
    public const string NameIdentifier = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier";
    public const string Role = "http://schemas.microsoft.com/ws/2008/06/identity/claims/role";
}

public static class AdminClaims
{
    public static string? Get(ClaimsPrincipal principal, params string[] names)
    {
        foreach (var name in names)
        {
            var value = principal.Claims.FirstOrDefault(c => string.Equals(c.Type, name, StringComparison.OrdinalIgnoreCase))?.Value;
            if (!string.IsNullOrWhiteSpace(value)) return value;
        }
        return null;
    }

    public static bool HasRequiredJwtClaims(ClaimsPrincipal principal)
    {
        var required = new[] { "sub", "jti", "username", "email", "role", "admin_status", "tenant" };
        return required.All(name => !string.IsNullOrWhiteSpace(Get(principal, name)));
    }
}

public sealed record AdminActor(
    string UserId,
    string Username,
    string Email,
    string Tenant,
    string Role,
    string AdminStatus)
{
    public static AdminActor From(HttpContext http)
    {
        return new AdminActor(
            AdminClaims.Get(http.User, "sub", "user_id", ClaimNames.NameIdentifier) ?? string.Empty,
            AdminClaims.Get(http.User, "username") ?? string.Empty,
            AdminClaims.Get(http.User, "email") ?? string.Empty,
            AdminClaims.Get(http.User, "tenant") ?? string.Empty,
            AdminClaims.Get(http.User, "role", ClaimNames.Role) ?? string.Empty,
            AdminClaims.Get(http.User, "admin_status") ?? string.Empty);
    }
}
