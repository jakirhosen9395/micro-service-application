using AdminService.Api.Configuration;
using System.Security.Claims;

namespace AdminService.Api.Security;

public static class AdminAuthorization
{
    public const string PolicyName = "ApprovedAdmin";

    public static bool IsApprovedAdmin(ClaimsPrincipal user, AdminSettings settings)
    {
        if (user.Identity?.IsAuthenticated != true) return false;
        if (!AdminClaims.HasRequiredJwtClaims(user)) return false;

        var role = AdminClaims.Get(user, "role", ClaimNames.Role);
        var adminStatus = AdminClaims.Get(user, "admin_status");
        var status = AdminClaims.Get(user, "status");
        var tenant = AdminClaims.Get(user, "tenant");

        if (!string.Equals(role, "admin", StringComparison.OrdinalIgnoreCase)) return false;
        if (!string.Equals(adminStatus, "approved", StringComparison.OrdinalIgnoreCase)) return false;
        if (!string.IsNullOrWhiteSpace(status) && !string.Equals(status, "active", StringComparison.OrdinalIgnoreCase)) return false;
        if (settings.SecurityRequireTenantMatch && !string.Equals(tenant, settings.Tenant, StringComparison.Ordinal)) return false;
        return true;
    }
}
