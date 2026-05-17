src/AdminService.Api/Endpoints/AdminEndpoints.cs
using AdminService.Api.Configuration;
using AdminService.Api.Contracts;
using AdminService.Api.Domain;
using AdminService.Api.Http;
using AdminService.Api.Infrastructure.Audit;
using AdminService.Api.Infrastructure.Redis;
using AdminService.Api.Persistence;
using AdminService.Api.Security;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;

namespace AdminService.Api.Endpoints;

public static class AdminEndpoints
{
    private static readonly HashSet<string> ReportFormats = new(StringComparer.OrdinalIgnoreCase) { "pdf", "csv", "json", "html", "xlsx" };

    public static RouteGroupBuilder MapAdminEndpoints(this RouteGroupBuilder group)
    {
        group.MapGet("/dashboard", DashboardAsync);
        group.MapGet("/summary", SummaryAsync);

        group.MapGet("/registrations", ListRegistrationsAsync);
        group.MapGet("/registrations/{requestId}", GetRegistrationAsync);
        group.MapPost("/registrations/{requestId}/approve", ApproveRegistrationAsync);
        group.MapPost("/registrations/{requestId}/reject", RejectRegistrationAsync);

        group.MapGet("/access-requests", ListAccessRequestsAsync);
        group.MapGet("/access-requests/{requestId}", GetAccessRequestAsync);
        group.MapPost("/access-requests/{requestId}/approve", ApproveAccessRequestAsync);
        group.MapPost("/access-requests/{requestId}/reject", RejectAccessRequestAsync);

        group.MapGet("/access-grants", ListAccessGrantsAsync);
        group.MapGet("/access-grants/{grantId}", GetAccessGrantAsync);
        group.MapPost("/access-grants/{grantId}/revoke", RevokeAccessGrantAsync);

        group.MapGet("/users", ListUsersAsync);
        group.MapGet("/users/{userId}", GetUserAsync);
        group.MapGet("/users/{userId}/activity", GetUserActivityAsync);
        group.MapGet("/users/{userId}/dashboard", GetUserDashboardAsync);
        group.MapGet("/users/{userId}/preferences", GetUserPreferencesAsync);
        group.MapGet("/users/{userId}/security-context", GetUserSecurityContextAsync);
        group.MapGet("/users/{userId}/rbac", GetUserRbacAsync);
        group.MapGet("/users/{userId}/effective-permissions", GetUserEffectivePermissionsAsync);
        group.MapGet("/users/{userId}/access-requests", GetUserAccessRequestsAsync);
        group.MapGet("/users/{userId}/access-grants", GetUserAccessGrantsAsync);
        group.MapGet("/users/{userId}/reports", GetUserReportsAsync);
        group.MapPost("/users/{userId}/suspend", SuspendUserAsync);
        group.MapPost("/users/{userId}/activate", ActivateUserAsync);
        group.MapPost("/users/{userId}/force-password-reset", ForcePasswordResetAsync);

        group.MapGet("/calculations", ListCalculationsAsync);
        group.MapGet("/calculations/summary", CalculationSummaryAsync);
        group.MapGet("/calculations/failed", ListFailedCalculationsAsync);
        group.MapGet("/calculations/history-cleared", ListHistoryClearedCalculationsAsync);
        group.MapGet("/calculations/audit", GetCalculationAuditAsync);
        group.MapGet("/calculations/users/{userId}", GetUserCalculationsAsync);
        group.MapGet("/calculations/users/{userId}/summary", GetUserCalculationSummaryAsync);
        group.MapGet("/calculations/users/{userId}/failed", GetUserFailedCalculationsAsync);
        group.MapGet("/calculations/users/{userId}/operations/{operation}", GetUserCalculationsByOperationAsync);
        group.MapGet("/calculations/{calculationId}", GetCalculationAsync);

        group.MapGet("/todos", ListTodosAsync);
        group.MapGet("/todos/summary", TodoSummaryAsync);
        group.MapGet("/todos/overdue", ListOverdueTodosAsync);
        group.MapGet("/todos/today", ListTodayTodosAsync);
        group.MapGet("/todos/archived", ListArchivedTodosAsync);
        group.MapGet("/todos/deleted", ListDeletedTodosAsync);
        group.MapGet("/todos/audit", GetTodoAuditAsync);
        group.MapGet("/todos/users/{userId}", GetUserTodosAsync);
        group.MapGet("/todos/users/{userId}/summary", GetUserTodoSummaryAsync);
        group.MapGet("/todos/users/{userId}/overdue", GetUserOverdueTodosAsync);
        group.MapGet("/todos/users/{userId}/today", GetUserTodayTodosAsync);
        group.MapGet("/todos/users/{userId}/activity", GetUserTodoActivityAsync);
        group.MapGet("/todos/{todoId}/history", GetTodoHistoryAsync);
        group.MapGet("/todos/{todoId}", GetTodoAsync);

        group.MapPost("/reports", RequestReportAsync);
        group.MapGet("/reports", ListReportsAsync);
        group.MapGet("/reports/summary", ReportSummaryAsync);
        group.MapGet("/reports/types", GetReportTypesAsync);
        group.MapGet("/reports/types/{reportType}", GetReportTypeAsync);
        group.MapGet("/reports/templates", GetReportTemplatesAsync);
        group.MapGet("/reports/templates/{templateId}", GetReportTemplateAsync);
        group.MapPost("/reports/templates", DisabledReportFeatureAsync);
        group.MapPut("/reports/templates/{templateId}", DisabledReportFeatureAsync);
        group.MapPost("/reports/templates/{templateId}/activate", DisabledReportFeatureAsync);
        group.MapPost("/reports/templates/{templateId}/deactivate", DisabledReportFeatureAsync);
        group.MapGet("/reports/schedules", GetReportSchedulesAsync);
        group.MapGet("/reports/schedules/{scheduleId}", GetReportScheduleAsync);
        group.MapPost("/reports/schedules", DisabledReportFeatureAsync);
        group.MapPut("/reports/schedules/{scheduleId}", DisabledReportFeatureAsync);
        group.MapPost("/reports/schedules/{scheduleId}/pause", DisabledReportFeatureAsync);
        group.MapPost("/reports/schedules/{scheduleId}/resume", DisabledReportFeatureAsync);
        group.MapDelete("/reports/schedules/{scheduleId}", DisabledReportFeatureAsync);
        group.MapGet("/reports/queue/summary", GetReportQueueSummaryAsync);
        group.MapGet("/reports/audit", GetReportAuditAsync);
        group.MapGet("/reports/audit/{eventId}", GetReportAuditEventAsync);
        group.MapGet("/reports/users/{userId}", GetUserReportsProjectionAsync);
        group.MapGet("/reports/{reportId}/metadata", GetReportMetadataAsync);
        group.MapGet("/reports/{reportId}/progress", GetReportProgressAsync);
        group.MapGet("/reports/{reportId}/events", GetReportEventsAsync);
        group.MapGet("/reports/{reportId}/files", GetReportFilesAsync);
        group.MapGet("/reports/{reportId}/preview", GetReportPreviewAsync);
        group.MapGet("/reports/{reportId}/download-info", GetReportDownloadInfoAsync);
        group.MapPost("/reports/{reportId}/cancel", CancelReportAsync);
        group.MapPost("/reports/{reportId}/retry", RetryReportAsync);
        group.MapPost("/reports/{reportId}/regenerate", RegenerateReportAsync);
        group.MapDelete("/reports/{reportId}", DeleteReportAsync);
        group.MapGet("/reports/{reportId}", GetReportAsync);

        group.MapGet("/audit", ListAuditAsync);
        group.MapGet("/audit/{eventId}", GetAuditAsync);
        return group;
    }

    private static async Task<IResult> DashboardAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AdminCache cache)
    {
        var actor = Actor(http, settings);
        var cached = await cache.GetAsync<JsonElement>($"dashboard:{actor.Tenant}");
        if (cached.ValueKind != JsonValueKind.Undefined) return ApiEnvelope.Ok(cached, "admin dashboard loaded", http);

        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var data = new
        {
            users = await db.AdminUserProjections.CountAsync(x => x.Tenant == actor.Tenant && x.DeletedAt == null, http.RequestAborted),
            pending_admin_registrations = await db.AdminRegistrationRequests.CountAsync(x => x.Tenant == actor.Tenant && x.Status == DecisionStatuses.Pending, http.RequestAborted),
            pending_access_requests = await db.AdminAccessRequests.CountAsync(x => x.Tenant == actor.Tenant && x.Status == DecisionStatuses.Pending, http.RequestAborted),
            active_access_grants = await db.AdminAccessGrants.CountAsync(x => x.Tenant == actor.Tenant && x.Status == GrantStatuses.Active && x.ExpiresAt > DateTimeOffset.UtcNow, http.RequestAborted),
            calculations = await db.AdminCalculationProjections.CountAsync(x => x.Tenant == actor.Tenant && x.DeletedAt == null, http.RequestAborted),
            todos = await db.AdminTodoProjections.CountAsync(x => x.Tenant == actor.Tenant && x.DeletedAt == null, http.RequestAborted),
            reports = await db.AdminReportProjections.CountAsync(x => x.Tenant == actor.Tenant && x.DeletedAt == null, http.RequestAborted),
            recent_audit = await db.AdminAuditEvents.AsNoTracking().Where(x => x.Tenant == actor.Tenant).OrderByDescending(x => x.CreatedAt).Take(10).ToListAsync(http.RequestAborted)
        };
        await cache.SetAsync($"dashboard:{actor.Tenant}", data);
        return ApiEnvelope.Ok(data, "admin dashboard loaded", http);
    }

    private static async Task<IResult> SummaryAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AdminCache cache)
    {
        var actor = Actor(http, settings);
        var cached = await cache.GetAsync<JsonElement>($"summary:{actor.Tenant}");
        if (cached.ValueKind != JsonValueKind.Undefined) return ApiEnvelope.Ok(cached, "admin summary loaded", http);

        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var data = new
        {
            admin_profiles = await db.AdminProfiles.CountAsync(x => x.Tenant == actor.Tenant && x.DeletedAt == null, http.RequestAborted),
            users = await db.AdminUserProjections.CountAsync(x => x.Tenant == actor.Tenant && x.DeletedAt == null, http.RequestAborted),
            registrations_by_status = await db.AdminRegistrationRequests.Where(x => x.Tenant == actor.Tenant).GroupBy(x => x.Status).Select(x => new { status = x.Key, count = x.Count() }).ToListAsync(http.RequestAborted),
            access_requests_by_status = await db.AdminAccessRequests.Where(x => x.Tenant == actor.Tenant).GroupBy(x => x.Status).Select(x => new { status = x.Key, count = x.Count() }).ToListAsync(http.RequestAborted),
            access_grants_by_status = await db.AdminAccessGrants.Where(x => x.Tenant == actor.Tenant).GroupBy(x => x.Status).Select(x => new { status = x.Key, count = x.Count() }).ToListAsync(http.RequestAborted),
            reports_by_status = await db.AdminReportProjections.Where(x => x.Tenant == actor.Tenant).GroupBy(x => x.Status).Select(x => new { status = x.Key, count = x.Count() }).ToListAsync(http.RequestAborted)
        };
        await cache.SetAsync($"summary:{actor.Tenant}", data);
        return ApiEnvelope.Ok(data, "admin summary loaded", http);
    }

    private static async Task<IResult> ListRegistrationsAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminRegistrationRequests.AsNoTracking().Where(x => x.Tenant == tenant && x.DeletedAt == null);
        query = ApplyStatus(query, http);
        return ApiEnvelope.Ok(await PageAsync(query.OrderByDescending(x => x.RequestedAt), http), "admin registration requests loaded", http);
    }

    private static async Task<IResult> GetRegistrationAsync(string requestId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminRegistrationRequests.AsNoTracking().FirstOrDefaultAsync(x => x.Tenant == tenant && x.RequestId == requestId && x.DeletedAt == null, http.RequestAborted);
        return entity is null ? ApiEnvelope.NotFound("admin registration request not found", http) : ApiEnvelope.Ok(entity, "admin registration request loaded", http);
    }

    private static Task<IResult> ApproveRegistrationAsync(string requestId, DecisionRequest request, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache)
        => DecideRegistrationAsync(requestId, DecisionStatuses.Approved, request, http, dbFactory, settings, audit, cache);

    private static Task<IResult> RejectRegistrationAsync(string requestId, DecisionRequest request, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache)
        => DecideRegistrationAsync(requestId, DecisionStatuses.Rejected, request, http, dbFactory, settings, audit, cache);

    private static async Task<IResult> DecideRegistrationAsync(string requestId, string decision, DecisionRequest request, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache)
    {
        var actor = Actor(http, settings);
        if (!await cache.AcquireLockAsync($"admin-registration-decision:{actor.Tenant}:{requestId}", TimeSpan.FromSeconds(30)))
        {
            return ApiEnvelope.Conflict("registration decision is already being processed", http);
        }

        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminRegistrationRequests.FirstOrDefaultAsync(x => x.Tenant == actor.Tenant && x.RequestId == requestId && x.DeletedAt == null, http.RequestAborted);
        if (entity is null) return ApiEnvelope.NotFound("admin registration request not found", http);
        if (entity.Status != DecisionStatuses.Pending) return ApiEnvelope.Conflict("admin registration request has already been decided", http, new { entity.Status });

        entity.Status = decision;
        entity.ReviewedAt = DateTimeOffset.UtcNow;
        entity.ReviewedBy = actor.UserId;
        entity.DecisionReason = request.Reason ?? string.Empty;

        if (decision == DecisionStatuses.Approved)
        {
            await UpsertAdminProfileAndUserProjectionAsync(db, settings, actor.Tenant, entity, http.RequestAborted);
        }

        var payload = new
        {
            request_id = entity.RequestId,
            user_id = entity.UserId,
            username = entity.Username,
            email = entity.Email,
            decision,
            status = decision,
            reviewed_by = actor.UserId,
            reason = request.Reason ?? string.Empty
        };
        await audit.RecordAsync(db, http, actor, $"admin.registration.{decision}", settings.AuthAdminDecisionsTopic, "admin_registration", entity.RequestId, entity.UserId, payload, http.RequestAborted);
        await db.SaveChangesAsync(http.RequestAborted);
        await cache.DeleteAsync($"dashboard:{actor.Tenant}", $"summary:{actor.Tenant}");
        return ApiEnvelope.Ok(new { entity.RequestId, entity.UserId, entity.Status }, decision == DecisionStatuses.Approved ? "admin registration approved" : "admin registration rejected", http);
    }

    private static async Task<IResult> ListAccessRequestsAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminAccessRequests.AsNoTracking().Where(x => x.Tenant == tenant && x.DeletedAt == null);
        query = ApplyStatus(query, http);
        return ApiEnvelope.Ok(await PageAsync(query.OrderByDescending(x => x.RequestedAt), http), "access requests loaded", http);
    }

    private static async Task<IResult> GetAccessRequestAsync(string requestId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminAccessRequests.AsNoTracking().FirstOrDefaultAsync(x => x.Tenant == tenant && x.RequestId == requestId && x.DeletedAt == null, http.RequestAborted);
        return entity is null ? ApiEnvelope.NotFound("access request not found", http) : ApiEnvelope.Ok(entity, "access request loaded", http);
    }

    private static async Task<IResult> ApproveAccessRequestAsync(string requestId, AccessApprovalRequest request, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache)
    {
        var actor = Actor(http, settings);
        if (!await cache.AcquireLockAsync($"access-request-decision:{actor.Tenant}:{requestId}", TimeSpan.FromSeconds(30))) return ApiEnvelope.Conflict("access request decision is already being processed", http);

        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminAccessRequests.FirstOrDefaultAsync(x => x.Tenant == actor.Tenant && x.RequestId == requestId && x.DeletedAt == null, http.RequestAborted);
        if (entity is null) return ApiEnvelope.NotFound("access request not found", http);
        if (entity.Status != DecisionStatuses.Pending) return ApiEnvelope.Conflict("access request has already been decided", http, new { entity.Status });

        var grantId = $"grant-{Guid.NewGuid():N}";
        var scope = string.IsNullOrWhiteSpace(request.Scope) ? entity.Scope : request.Scope!;
        var expiresAt = request.ExpiresAt ?? entity.ExpiresAt ?? DateTimeOffset.UtcNow.AddDays(settings.AccessGrantDefaultTtlDays);
        entity.Status = DecisionStatuses.Approved;
        entity.Scope = scope;
        entity.ExpiresAt = expiresAt;
        entity.ReviewedAt = DateTimeOffset.UtcNow;
        entity.ReviewedBy = actor.UserId;
        entity.DecisionReason = request.Reason ?? string.Empty;

        var grant = new AdminAccessGrant
        {
            Tenant = actor.Tenant,
            GrantId = grantId,
            RequestId = entity.RequestId,
            RequesterUserId = entity.RequesterUserId,
            TargetUserId = entity.TargetUserId,
            ResourceType = entity.ResourceType,
            Scope = scope,
            Status = GrantStatuses.Active,
            ApprovedBy = actor.UserId,
            ApprovedAt = DateTimeOffset.UtcNow,
            ExpiresAt = expiresAt
        };
        db.AdminAccessGrants.Add(grant);

        var approvalPayload = new
        {
            request_id = entity.RequestId,
            requester_user_id = entity.RequesterUserId,
            target_user_id = entity.TargetUserId,
            resource_type = entity.ResourceType,
            scope,
            status = DecisionStatuses.Approved,
            reviewed_by = actor.UserId,
            expires_at = expiresAt,
            reason = request.Reason ?? string.Empty
        };
        await audit.RecordAsync(db, http, actor, "access.request.approved", settings.AccessEventsTopic, "access_request", entity.RequestId, entity.TargetUserId, approvalPayload, http.RequestAborted);

        var grantPayload = new
        {
            grant_id = grant.GrantId,
            request_id = grant.RequestId,
            requester_user_id = grant.RequesterUserId,
            target_user_id = grant.TargetUserId,
            resource_type = grant.ResourceType,
            scope = grant.Scope,
            status = grant.Status,
            approved_by = actor.UserId,
            approved_at = grant.ApprovedAt,
            expires_at = grant.ExpiresAt
        };
        await audit.RecordAsync(db, http, actor, "access.grant.created", settings.AccessEventsTopic, "access_grant", grant.GrantId, grant.TargetUserId, grantPayload, http.RequestAborted);
        await db.SaveChangesAsync(http.RequestAborted);
        await cache.DeleteAsync($"dashboard:{actor.Tenant}", $"summary:{actor.Tenant}");
        return ApiEnvelope.Ok(new { entity.RequestId, grant.GrantId, entity.Status, grant.ExpiresAt }, "access request approved", http);
    }

    private static async Task<IResult> RejectAccessRequestAsync(string requestId, DecisionRequest request, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache)
    {
        var actor = Actor(http, settings);
        if (!await cache.AcquireLockAsync($"access-request-decision:{actor.Tenant}:{requestId}", TimeSpan.FromSeconds(30))) return ApiEnvelope.Conflict("access request decision is already being processed", http);

        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminAccessRequests.FirstOrDefaultAsync(x => x.Tenant == actor.Tenant && x.RequestId == requestId && x.DeletedAt == null, http.RequestAborted);
        if (entity is null) return ApiEnvelope.NotFound("access request not found", http);
        if (entity.Status != DecisionStatuses.Pending) return ApiEnvelope.Conflict("access request has already been decided", http, new { entity.Status });

        entity.Status = DecisionStatuses.Rejected;
        entity.ReviewedAt = DateTimeOffset.UtcNow;
        entity.ReviewedBy = actor.UserId;
        entity.DecisionReason = request.Reason ?? string.Empty;
        var payload = new
        {
            request_id = entity.RequestId,
            requester_user_id = entity.RequesterUserId,
            target_user_id = entity.TargetUserId,
            status = entity.Status,
            reviewed_by = actor.UserId,
            reason = request.Reason ?? string.Empty
        };
        await audit.RecordAsync(db, http, actor, "access.request.rejected", settings.AccessEventsTopic, "access_request", entity.RequestId, entity.TargetUserId, payload, http.RequestAborted);
        await db.SaveChangesAsync(http.RequestAborted);
        await cache.DeleteAsync($"dashboard:{actor.Tenant}", $"summary:{actor.Tenant}");
        return ApiEnvelope.Ok(new { entity.RequestId, entity.Status }, "access request rejected", http);
    }

    private static async Task<IResult> ListAccessGrantsAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminAccessGrants.AsNoTracking().Where(x => x.Tenant == tenant && x.DeletedAt == null);
        query = ApplyStatus(query, http);
        return ApiEnvelope.Ok(await PageAsync(query.OrderByDescending(x => x.ApprovedAt), http), "access grants loaded", http);
    }

    private static async Task<IResult> GetAccessGrantAsync(string grantId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminAccessGrants.AsNoTracking().FirstOrDefaultAsync(x => x.Tenant == tenant && x.GrantId == grantId && x.DeletedAt == null, http.RequestAborted);
        return entity is null ? ApiEnvelope.NotFound("access grant not found", http) : ApiEnvelope.Ok(entity, "access grant loaded", http);
    }

    private static async Task<IResult> RevokeAccessGrantAsync(string grantId, DecisionRequest request, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache)
    {
        var actor = Actor(http, settings);
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminAccessGrants.FirstOrDefaultAsync(x => x.Tenant == actor.Tenant && x.GrantId == grantId && x.DeletedAt == null, http.RequestAborted);
        if (entity is null) return ApiEnvelope.NotFound("access grant not found", http);
        if (entity.Status != GrantStatuses.Active) return ApiEnvelope.Conflict("access grant is not active", http, new { entity.Status });
        entity.Status = GrantStatuses.Revoked;
        entity.RevokedAt = DateTimeOffset.UtcNow;
        entity.RevokedBy = actor.UserId;
        entity.RevokeReason = request.Reason ?? string.Empty;
        var payload = new
        {
            grant_id = entity.GrantId,
            request_id = entity.RequestId,
            requester_user_id = entity.RequesterUserId,
            target_user_id = entity.TargetUserId,
            resource_type = entity.ResourceType,
            scope = entity.Scope,
            status = entity.Status,
            revoked_by = actor.UserId,
            revoked_at = entity.RevokedAt,
            reason = request.Reason ?? string.Empty
        };
        await audit.RecordAsync(db, http, actor, "access.grant.revoked", settings.AccessEventsTopic, "access_grant", entity.GrantId, entity.TargetUserId, payload, http.RequestAborted);
        await db.SaveChangesAsync(http.RequestAborted);
        await cache.DeleteAsync($"dashboard:{actor.Tenant}", $"summary:{actor.Tenant}");
        return ApiEnvelope.Ok(new { entity.GrantId, entity.Status }, "access grant revoked", http);
    }

    private static async Task<IResult> ListUsersAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminUserProjections.AsNoTracking().Where(x => x.Tenant == tenant && x.DeletedAt == null);
        query = ApplyStatus(query, http);
        return ApiEnvelope.Ok(await PageAsync(query.OrderByDescending(x => x.UpdatedAt), http), "users loaded", http);
    }

    private static async Task<IResult> GetUserAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminUserProjections.AsNoTracking().FirstOrDefaultAsync(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null, http.RequestAborted);
        return entity is null ? ApiEnvelope.NotFound("user projection not found", http) : ApiEnvelope.Ok(entity, "user projection loaded", http);
    }

    private static async Task<IResult> GetUserActivityAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var data = await db.AdminAuditEvents.AsNoTracking().Where(x => x.Tenant == tenant && (x.TargetUserId == userId || x.AdminUserId == userId)).OrderByDescending(x => x.CreatedAt).Take(Limit(http)).ToListAsync(http.RequestAborted);
        return ApiEnvelope.Ok(data, "user activity loaded", http);
    }

    private static async Task<IResult> GetUserDashboardAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var user = await db.AdminUserProjections.AsNoTracking().FirstOrDefaultAsync(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null, http.RequestAborted);
        if (user is null) return ApiEnvelope.NotFound("user projection not found", http);
        var data = new
        {
            user_id = userId,
            calculations = await db.AdminCalculationProjections.CountAsync(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null, http.RequestAborted),
            todos = await db.AdminTodoProjections.CountAsync(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null, http.RequestAborted),
            reports = await db.AdminReportProjections.CountAsync(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null, http.RequestAborted),
            active_access_grants = await db.AdminAccessGrants.CountAsync(x => x.Tenant == tenant && x.DeletedAt == null && x.Status == GrantStatuses.Active && (x.TargetUserId == userId || x.RequesterUserId == userId), http.RequestAborted),
            user
        };
        return ApiEnvelope.Ok(data, "user dashboard loaded", http);
    }

    private static async Task<IResult> GetUserPreferencesAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var user = await LoadUserAsync(userId, http, dbFactory, settings);
        return user is null ? ApiEnvelope.NotFound("user projection not found", http) : ApiEnvelope.Ok(new { user_id = userId, preferences = PayloadValue(user.Payload, "preferences") }, "user preferences loaded", http);
    }

    private static async Task<IResult> GetUserSecurityContextAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var user = await LoadUserAsync(userId, http, dbFactory, settings);
        if (user is null) return ApiEnvelope.NotFound("user projection not found", http);
        return ApiEnvelope.Ok(new { user.UserId, user.Username, user.Email, user.Role, user.AdminStatus, user.Status, user.Tenant, user.LastSeenAt }, "user security context loaded", http);
    }

    private static async Task<IResult> GetUserRbacAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var user = await LoadUserAsync(userId, http, dbFactory, settings);
        if (user is null) return ApiEnvelope.NotFound("user projection not found", http);
        var roles = new[] { user.Role }.Where(x => !string.IsNullOrWhiteSpace(x)).ToArray();
        return ApiEnvelope.Ok(new { user_id = userId, roles, admin_status = user.AdminStatus, status = user.Status }, "user rbac loaded", http);
    }

    private static async Task<IResult> GetUserEffectivePermissionsAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var user = await db.AdminUserProjections.AsNoTracking().FirstOrDefaultAsync(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null, http.RequestAborted);
        if (user is null) return ApiEnvelope.NotFound("user projection not found", http);
        var grants = await db.AdminAccessGrants.AsNoTracking()
            .Where(x => x.Tenant == tenant && x.DeletedAt == null && x.Status == GrantStatuses.Active && x.ExpiresAt > DateTimeOffset.UtcNow && (x.TargetUserId == userId || x.RequesterUserId == userId))
            .OrderByDescending(x => x.ApprovedAt)
            .ToListAsync(http.RequestAborted);
        return ApiEnvelope.Ok(new { user_id = userId, role = user.Role, admin_status = user.AdminStatus, scopes = grants.Select(x => x.Scope).Distinct().OrderBy(x => x), grants }, "user effective permissions loaded", http);
    }

    private static async Task<IResult> GetUserAccessRequestsAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminAccessRequests.AsNoTracking().Where(x => x.Tenant == tenant && x.DeletedAt == null && (x.TargetUserId == userId || x.RequesterUserId == userId)).OrderByDescending(x => x.RequestedAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "user access requests loaded", http);
    }

    private static async Task<IResult> GetUserAccessGrantsAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminAccessGrants.AsNoTracking().Where(x => x.Tenant == tenant && x.DeletedAt == null && (x.TargetUserId == userId || x.RequesterUserId == userId));
        return ApiEnvelope.Ok(await PageAsync(query.OrderByDescending(x => x.ApprovedAt), http), "user access grants loaded", http);
    }

    private static async Task<IResult> GetUserReportsAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
        => await GetUserReportsProjectionAsync(userId, http, dbFactory, settings);

    private static Task<IResult> SuspendUserAsync(string userId, DecisionRequest request, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache)
        => UserCommandAsync(userId, "admin.user.suspended", "suspended", request, http, dbFactory, settings, audit, cache, "user suspended");

    private static Task<IResult> ActivateUserAsync(string userId, DecisionRequest request, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache)
        => UserCommandAsync(userId, "admin.user.activated", "active", request, http, dbFactory, settings, audit, cache, "user activated");

    private static async Task<IResult> ForcePasswordResetAsync(string userId, DecisionRequest request, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache)
    {
        var actor = Actor(http, settings);
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);

        var user = await db.AdminUserProjections
            .FirstOrDefaultAsync(x => x.Tenant == actor.Tenant && x.UserId == userId && x.DeletedAt == null, http.RequestAborted);

        if (user is null)
        {
            return ApiEnvelope.NotFound("user projection not found", http);
        }

        var payload = new { user_id = userId, requested_by = actor.UserId, reason = request.Reason ?? string.Empty };
        await audit.RecordAsync(db, http, actor, "admin.user.force_password_reset_requested", settings.KafkaEventsTopic, "user", userId, userId, payload, http.RequestAborted);
        await db.SaveChangesAsync(http.RequestAborted);
        await cache.DeleteAsync($"dashboard:{actor.Tenant}", $"summary:{actor.Tenant}", $"user:{actor.Tenant}:{userId}");
        return ApiEnvelope.Ok(new { user_id = userId, command = "force_password_reset" }, "force password reset command emitted", http);
    }

    private static async Task<IResult> UserCommandAsync(string userId, string eventType, string newStatus, DecisionRequest request, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache, string message)
    {
        var actor = Actor(http, settings);
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);

        var user = await db.AdminUserProjections
            .FirstOrDefaultAsync(x => x.Tenant == actor.Tenant && x.UserId == userId && x.DeletedAt == null, http.RequestAborted);

        if (user is null)
        {
            return ApiEnvelope.NotFound("user projection not found", http);
        }

        user.Status = newStatus;
        user.UpdatedAt = DateTimeOffset.UtcNow;

        var payload = new { user_id = userId, status = newStatus, requested_by = actor.UserId, reason = request.Reason ?? string.Empty };
        await audit.RecordAsync(db, http, actor, eventType, settings.KafkaEventsTopic, "user", userId, userId, payload, http.RequestAborted);
        await db.SaveChangesAsync(http.RequestAborted);
        await cache.DeleteAsync($"dashboard:{actor.Tenant}", $"summary:{actor.Tenant}", $"user:{actor.Tenant}:{userId}");
        return ApiEnvelope.Ok(new { user_id = userId, status = newStatus }, message, http);
    }

    private static async Task<IResult> ListCalculationsAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminCalculationProjections.AsNoTracking().Where(x => x.Tenant == tenant && x.DeletedAt == null);
        return ApiEnvelope.Ok(await PageAsync(query.OrderByDescending(x => x.OccurredAt), http), "calculation projections loaded", http);
    }

    private static async Task<IResult> ListFailedCalculationsAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminCalculationProjections.AsNoTracking().Where(x => x.Tenant == tenant && x.DeletedAt == null && x.Status.ToLower() == "failed").OrderByDescending(x => x.OccurredAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "failed calculation projections loaded", http);
    }

    private static async Task<IResult> ListHistoryClearedCalculationsAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);

        // Payload is mapped as PostgreSQL jsonb, so do not use string Contains()
        // against Payload inside EF queries. The calculation projection status is
        // already derived from the event name, e.g. calculation.history.cleared -> cleared.
        var query = db.AdminCalculationProjections
            .AsNoTracking()
            .Where(x => x.Tenant == tenant && x.DeletedAt == null && x.Status.ToLower().Contains("cleared"))
            .OrderByDescending(x => x.OccurredAt);

        return ApiEnvelope.Ok(await PageAsync(query, http), "history-cleared calculation projections loaded", http);
    }

    private static async Task<IResult> GetCalculationAuditAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminAuditEvents.AsNoTracking().Where(x => x.Tenant == tenant && (x.ResourceType == "calculation" || x.EventType.StartsWith("calculation."))).OrderByDescending(x => x.CreatedAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "calculation audit events loaded", http);
    }

    private static async Task<IResult> GetCalculationAsync(string calculationId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminCalculationProjections.AsNoTracking().FirstOrDefaultAsync(x => x.Tenant == tenant && x.CalculationId == calculationId && x.DeletedAt == null, http.RequestAborted);
        return entity is null ? ApiEnvelope.NotFound("calculation projection not found", http) : ApiEnvelope.Ok(entity, "calculation projection loaded", http);
    }

    private static async Task<IResult> GetUserCalculationsAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminCalculationProjections.AsNoTracking().Where(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null).OrderByDescending(x => x.OccurredAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "user calculation projections loaded", http);
    }

    private static async Task<IResult> GetUserCalculationSummaryAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var data = new
        {
            user_id = userId,
            total = await db.AdminCalculationProjections.CountAsync(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null, http.RequestAborted),
            by_status = await db.AdminCalculationProjections.Where(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null).GroupBy(x => x.Status).Select(x => new { status = x.Key, count = x.Count() }).ToListAsync(http.RequestAborted),
            by_operation = await db.AdminCalculationProjections.Where(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null).GroupBy(x => x.Operation).Select(x => new { operation = x.Key, count = x.Count() }).ToListAsync(http.RequestAborted)
        };
        return ApiEnvelope.Ok(data, "user calculation summary loaded", http);
    }

    private static async Task<IResult> GetUserFailedCalculationsAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminCalculationProjections.AsNoTracking().Where(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null && x.Status.ToLower() == "failed").OrderByDescending(x => x.OccurredAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "user failed calculation projections loaded", http);
    }

    private static async Task<IResult> GetUserCalculationsByOperationAsync(string userId, string operation, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var normalized = operation.ToUpperInvariant();
        var query = db.AdminCalculationProjections.AsNoTracking().Where(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null && x.Operation.ToUpper() == normalized).OrderByDescending(x => x.OccurredAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "user calculation projections by operation loaded", http);
    }

    private static async Task<IResult> CalculationSummaryAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var data = new
        {
            total = await db.AdminCalculationProjections.CountAsync(x => x.Tenant == tenant && x.DeletedAt == null, http.RequestAborted),
            by_status = await db.AdminCalculationProjections.Where(x => x.Tenant == tenant && x.DeletedAt == null).GroupBy(x => x.Status).Select(x => new { status = x.Key, count = x.Count() }).ToListAsync(http.RequestAborted),
            by_operation = await db.AdminCalculationProjections.Where(x => x.Tenant == tenant && x.DeletedAt == null).GroupBy(x => x.Operation).Select(x => new { operation = x.Key, count = x.Count() }).ToListAsync(http.RequestAborted)
        };
        return ApiEnvelope.Ok(data, "calculation summary loaded", http);
    }

    private static async Task<IResult> ListTodosAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminTodoProjections.AsNoTracking().Where(x => x.Tenant == tenant && x.DeletedAt == null);
        query = ApplyStatus(query, http);
        return ApiEnvelope.Ok(await PageAsync(query.OrderByDescending(x => x.OccurredAt), http), "todo projections loaded", http);
    }

    private static async Task<IResult> ListOverdueTodosAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);

        // Payload is jsonb. Fetch active tenant rows with normal indexed columns,
        // then parse due_date safely in application code.
        var now = DateTimeOffset.UtcNow;
        var candidates = await db.AdminTodoProjections
            .AsNoTracking()
            .Where(x => x.Tenant == tenant && x.DeletedAt == null)
            .OrderByDescending(x => x.OccurredAt)
            .ToListAsync(http.RequestAborted);

        var overdue = candidates.Where(x => IsOverdueTodoProjection(x, now)).ToList();
        return ApiEnvelope.Ok(PageList(overdue, http), "overdue todo projections loaded", http);
    }

    private static async Task<IResult> ListTodayTodosAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        var today = new DateTimeOffset(DateTime.UtcNow.Date, TimeSpan.Zero);
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminTodoProjections.AsNoTracking().Where(x => x.Tenant == tenant && x.DeletedAt == null && x.OccurredAt >= today && x.OccurredAt < today.AddDays(1)).OrderByDescending(x => x.OccurredAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "today todo projections loaded", http);
    }

    private static async Task<IResult> ListArchivedTodosAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminTodoProjections.AsNoTracking().Where(x => x.Tenant == tenant && x.DeletedAt == null && x.Status.ToLower() == "archived").OrderByDescending(x => x.OccurredAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "archived todo projections loaded", http);
    }

    private static async Task<IResult> ListDeletedTodosAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminTodoProjections.AsNoTracking().Where(x => x.Tenant == tenant && (x.DeletedAt != null || x.Status.ToLower().Contains("deleted"))).OrderByDescending(x => x.OccurredAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "deleted todo projections loaded", http);
    }

    private static async Task<IResult> GetTodoAuditAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminAuditEvents.AsNoTracking().Where(x => x.Tenant == tenant && (x.ResourceType == "todo" || x.EventType.StartsWith("todo."))).OrderByDescending(x => x.CreatedAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "todo audit events loaded", http);
    }

    private static async Task<IResult> GetTodoAsync(string todoId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminTodoProjections.AsNoTracking().FirstOrDefaultAsync(x => x.Tenant == tenant && x.TodoId == todoId && x.DeletedAt == null, http.RequestAborted);
        return entity is null ? ApiEnvelope.NotFound("todo projection not found", http) : ApiEnvelope.Ok(entity, "todo projection loaded", http);
    }

    private static async Task<IResult> GetUserTodosAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminTodoProjections.AsNoTracking().Where(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null).OrderByDescending(x => x.OccurredAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "user todo projections loaded", http);
    }

    private static async Task<IResult> GetUserTodoSummaryAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var data = new
        {
            user_id = userId,
            total = await db.AdminTodoProjections.CountAsync(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null, http.RequestAborted),
            by_status = await db.AdminTodoProjections.Where(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null).GroupBy(x => x.Status).Select(x => new { status = x.Key, count = x.Count() }).ToListAsync(http.RequestAborted)
        };
        return ApiEnvelope.Ok(data, "user todo summary loaded", http);
    }

    private static async Task<IResult> GetUserOverdueTodosAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);

        // Payload is jsonb. Fetch this user's active rows with normal indexed columns,
        // then parse due_date safely in application code.
        var now = DateTimeOffset.UtcNow;
        var candidates = await db.AdminTodoProjections
            .AsNoTracking()
            .Where(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null)
            .OrderByDescending(x => x.OccurredAt)
            .ToListAsync(http.RequestAborted);

        var overdue = candidates.Where(x => IsOverdueTodoProjection(x, now)).ToList();
        return ApiEnvelope.Ok(PageList(overdue, http), "user overdue todo projections loaded", http);
    }

    private static async Task<IResult> GetUserTodayTodosAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        var today = new DateTimeOffset(DateTime.UtcNow.Date, TimeSpan.Zero);
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminTodoProjections.AsNoTracking().Where(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null && x.OccurredAt >= today && x.OccurredAt < today.AddDays(1)).OrderByDescending(x => x.OccurredAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "user today todo projections loaded", http);
    }

    private static async Task<IResult> GetUserTodoActivityAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminTodoProjections.AsNoTracking().Where(x => x.Tenant == tenant && x.UserId == userId).OrderByDescending(x => x.OccurredAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "user todo activity loaded", http);
    }

    private static async Task<IResult> GetTodoHistoryAsync(string todoId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);

        var exists = await db.AdminTodoProjections
            .AsNoTracking()
            .AnyAsync(x => x.Tenant == tenant && x.TodoId == todoId, http.RequestAborted);

        if (!exists)
        {
            return ApiEnvelope.NotFound("todo projection not found", http);
        }

        var query = db.AdminTodoProjections
            .AsNoTracking()
            .Where(x => x.Tenant == tenant && x.TodoId == todoId)
            .OrderByDescending(x => x.OccurredAt);

        return ApiEnvelope.Ok(await PageAsync(query, http), "todo history loaded", http);
    }

    private static async Task<IResult> TodoSummaryAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var data = new
        {
            total = await db.AdminTodoProjections.CountAsync(x => x.Tenant == tenant && x.DeletedAt == null, http.RequestAborted),
            by_status = await db.AdminTodoProjections.Where(x => x.Tenant == tenant && x.DeletedAt == null).GroupBy(x => x.Status).Select(x => new { status = x.Key, count = x.Count() }).ToListAsync(http.RequestAborted)
        };
        return ApiEnvelope.Ok(data, "todo summary loaded", http);
    }

    private static IResult GetReportTypesAsync(HttpContext http)
    {
        var types = new[]
        {
            new { report_type = "admin_activity_report", formats = ReportFormats.OrderBy(x => x), description = "Admin audit and control-plane activity." },
            new { report_type = "user_activity_report", formats = ReportFormats.OrderBy(x => x), description = "User projection, activity, and access-grant report." },
            new { report_type = "calculator_history_report", formats = ReportFormats.OrderBy(x => x), description = "Projected calculation history report." },
            new { report_type = "todo_history_report", formats = ReportFormats.OrderBy(x => x), description = "Projected todo history report." },
            new { report_type = "report_lifecycle_report", formats = ReportFormats.OrderBy(x => x), description = "Report request and lifecycle report." }
        };
        return ApiEnvelope.Ok(types, "admin report types loaded", http);
    }

    private static IResult GetReportTypeAsync(string reportType, HttpContext http)
    {
        var data = new { report_type = reportType, formats = ReportFormats.OrderBy(x => x), filters = new { date_from = "optional date", date_to = "optional date", target_user_id = "optional string" }, options = new { }, enabled = true };
        return ApiEnvelope.Ok(data, "admin report type loaded", http);
    }

    private static IResult GetReportTemplatesAsync(HttpContext http)
        => ApiEnvelope.Ok(Array.Empty<object>(), "admin report templates are disabled in this build", http);

    private static IResult GetReportTemplateAsync(string templateId, HttpContext http)
        => ApiEnvelope.Ok(new { template_id = templateId, enabled = false, status = "disabled" }, "admin report template is disabled in this build", http);

    private static IResult GetReportSchedulesAsync(HttpContext http)
        => ApiEnvelope.Ok(Array.Empty<object>(), "admin report schedules are disabled in this build", http);

    private static IResult GetReportScheduleAsync(string scheduleId, HttpContext http)
        => ApiEnvelope.Ok(new { schedule_id = scheduleId, enabled = false, status = "disabled" }, "admin report schedule is disabled in this build", http);

    private static IResult DisabledReportFeatureAsync(HttpContext http)
        => ApiEnvelope.Error("admin report templates and schedules are disabled in this build", "NOT_IMPLEMENTED", http, StatusCodes.Status501NotImplemented);

    private static async Task<IResult> RequestReportAsync(AdminReportRequest request, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache)
    {
        if (string.IsNullOrWhiteSpace(request.ReportType)) return ApiEnvelope.BadRequest("report_type is required", http);
        if (!ReportFormats.Contains(request.Format)) return ApiEnvelope.BadRequest("unsupported report format", http, new { allowed = ReportFormats.OrderBy(x => x) });

        var actor = Actor(http, settings);
        var targetUserId = string.IsNullOrWhiteSpace(request.TargetUserId) ? actor.UserId : request.TargetUserId!;
        var reportId = $"report-{Guid.NewGuid():N}";
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var payload = new
        {
            report_id = reportId,
            report_type = request.ReportType,
            target_user_id = targetUserId,
            format = request.Format.ToLowerInvariant(),
            date_from = request.DateFrom,
            date_to = request.DateTo,
            filters = request.Filters,
            options = request.Options,
            requested_by = actor.UserId,
            status = "requested"
        };
        db.AdminReportProjections.Add(new AdminReportProjection
        {
            Tenant = actor.Tenant,
            ReportId = reportId,
            UserId = targetUserId,
            ReportType = request.ReportType,
            Format = request.Format.ToLowerInvariant(),
            Status = "requested",
            RequestedBy = actor.UserId,
            RequestedAt = DateTimeOffset.UtcNow,
            Payload = JsonSerializer.Serialize(payload, JsonOptionsFactory.Options)
        });
        await audit.RecordAsync(db, http, actor, "admin.report.requested", settings.KafkaEventsTopic, "report", reportId, targetUserId, payload, http.RequestAborted);
        await db.SaveChangesAsync(http.RequestAborted);
        await cache.DeleteAsync($"dashboard:{actor.Tenant}", $"summary:{actor.Tenant}");
        return ApiEnvelope.Created(new { report_id = reportId, status = "requested" }, "admin report requested", http);
    }

    private static async Task<IResult> ListReportsAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminReportProjections.AsNoTracking().Where(x => x.Tenant == tenant && x.DeletedAt == null).OrderByDescending(x => x.RequestedAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "report projections loaded", http);
    }

    private static async Task<IResult> GetReportAsync(string reportId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminReportProjections.AsNoTracking().FirstOrDefaultAsync(x => x.Tenant == tenant && x.ReportId == reportId && x.DeletedAt == null, http.RequestAborted);
        return entity is null ? ApiEnvelope.NotFound("report projection not found", http) : ApiEnvelope.Ok(entity, "report projection loaded", http);
    }

    private static async Task<IResult> GetUserReportsProjectionAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminReportProjections.AsNoTracking().Where(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null).OrderByDescending(x => x.RequestedAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "user report projections loaded", http);
    }

    private static async Task<IResult> ReportSummaryAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var data = new
        {
            total = await db.AdminReportProjections.CountAsync(x => x.Tenant == tenant && x.DeletedAt == null, http.RequestAborted),
            by_status = await db.AdminReportProjections.Where(x => x.Tenant == tenant && x.DeletedAt == null).GroupBy(x => x.Status).Select(x => new { status = x.Key, count = x.Count() }).ToListAsync(http.RequestAborted),
            by_format = await db.AdminReportProjections.Where(x => x.Tenant == tenant && x.DeletedAt == null).GroupBy(x => x.Format).Select(x => new { format = x.Key, count = x.Count() }).ToListAsync(http.RequestAborted)
        };
        return ApiEnvelope.Ok(data, "report summary loaded", http);
    }

    private static async Task<IResult> GetReportMetadataAsync(string reportId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var entity = await LoadReportAsync(reportId, http, dbFactory, settings);
        return entity is null ? ApiEnvelope.NotFound("report projection not found", http) : ApiEnvelope.Ok(new { entity.ReportId, entity.ReportType, entity.Format, entity.Status, entity.RequestedBy, entity.RequestedAt, metadata = PayloadValue(entity.Payload, "metadata") }, "report metadata loaded", http);
    }

    private static async Task<IResult> GetReportProgressAsync(string reportId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var entity = await LoadReportAsync(reportId, http, dbFactory, settings);
        return entity is null ? ApiEnvelope.NotFound("report projection not found", http) : ApiEnvelope.Ok(new { entity.ReportId, entity.Status, progress = PayloadValue(entity.Payload, "progress") }, "report progress loaded", http);
    }

    private static async Task<IResult> GetReportEventsAsync(string reportId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminAuditEvents.AsNoTracking().Where(x => x.Tenant == tenant && x.ResourceType == "report" && x.ResourceId == reportId).OrderByDescending(x => x.CreatedAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "report events loaded", http);
    }

    private static async Task<IResult> GetReportFilesAsync(string reportId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var entity = await LoadReportAsync(reportId, http, dbFactory, settings);
        return entity is null ? ApiEnvelope.NotFound("report projection not found", http) : ApiEnvelope.Ok(new { report_id = reportId, files = PayloadValue(entity.Payload, "files"), s3_bucket = PayloadValue(entity.Payload, "s3_bucket"), s3_object_key = PayloadValue(entity.Payload, "s3_object_key") }, "report files loaded", http);
    }

    private static async Task<IResult> GetReportPreviewAsync(string reportId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var entity = await LoadReportAsync(reportId, http, dbFactory, settings);
        return entity is null ? ApiEnvelope.NotFound("report projection not found", http) : ApiEnvelope.Ok(new { report_id = reportId, preview_supported = PayloadValue(entity.Payload, "preview_supported"), preview = PayloadValue(entity.Payload, "preview") }, "report preview loaded", http);
    }

    private static async Task<IResult> GetReportDownloadInfoAsync(string reportId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var entity = await LoadReportAsync(reportId, http, dbFactory, settings);
        return entity is null ? ApiEnvelope.NotFound("report projection not found", http) : ApiEnvelope.Ok(new { report_id = reportId, file_name = PayloadValue(entity.Payload, "file_name"), content_type = PayloadValue(entity.Payload, "content_type"), file_size_bytes = PayloadValue(entity.Payload, "file_size_bytes"), s3_bucket = PayloadValue(entity.Payload, "s3_bucket"), s3_object_key = PayloadValue(entity.Payload, "s3_object_key") }, "report download info loaded", http);
    }

    private static async Task<IResult> GetReportQueueSummaryAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var queued = await db.AdminReportProjections.CountAsync(x => x.Tenant == tenant && x.DeletedAt == null && (x.Status == "requested" || x.Status == "queued"), http.RequestAborted);
        var processing = await db.AdminReportProjections.CountAsync(x => x.Tenant == tenant && x.DeletedAt == null && x.Status == "processing", http.RequestAborted);
        var failed = await db.AdminReportProjections.CountAsync(x => x.Tenant == tenant && x.DeletedAt == null && x.Status == "failed", http.RequestAborted);
        return ApiEnvelope.Ok(new { queued, processing, failed }, "report queue summary loaded", http);
    }

    private static async Task<IResult> GetReportAuditAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminAuditEvents.AsNoTracking().Where(x => x.Tenant == tenant && (x.ResourceType == "report" || x.EventType.StartsWith("report.") || x.EventType.StartsWith("admin.report."))).OrderByDescending(x => x.CreatedAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "report audit events loaded", http);
    }

    private static async Task<IResult> GetReportAuditEventAsync(string eventId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminAuditEvents.AsNoTracking().FirstOrDefaultAsync(x => x.Tenant == tenant && x.EventId == eventId && (x.ResourceType == "report" || x.EventType.StartsWith("report.") || x.EventType.StartsWith("admin.report.")), http.RequestAborted);
        return entity is null ? ApiEnvelope.NotFound("report audit event not found", http) : ApiEnvelope.Ok(entity, "report audit event loaded", http);
    }

    private static Task<IResult> RetryReportAsync(string reportId, DecisionRequest request, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache)
        => ReportCommandAsync(reportId, request, "admin.report.retry_requested", "retry_requested", "report retry requested", http, dbFactory, settings, audit, cache);

    private static Task<IResult> RegenerateReportAsync(string reportId, DecisionRequest request, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache)
        => ReportCommandAsync(reportId, request, "admin.report.regenerate_requested", "regenerate_requested", "report regenerate requested", http, dbFactory, settings, audit, cache);

    private static Task<IResult> DeleteReportAsync(string reportId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache)
        => ReportCommandAsync(reportId, new DecisionRequest("Deleted by approved admin"), "admin.report.deleted", "deleted", "report delete requested", http, dbFactory, settings, audit, cache, softDelete: true);

    private static async Task<IResult> CancelReportAsync(string reportId, DecisionRequest request, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache)
    {
        var actor = Actor(http, settings);
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminReportProjections.FirstOrDefaultAsync(x => x.Tenant == actor.Tenant && x.ReportId == reportId && x.DeletedAt == null, http.RequestAborted);
        if (entity is null) return ApiEnvelope.NotFound("report projection not found", http);
        entity.Status = "cancel_requested";
        var payload = new { report_id = entity.ReportId, target_user_id = entity.UserId, status = entity.Status, requested_by = actor.UserId, reason = request.Reason ?? string.Empty };
        await audit.RecordAsync(db, http, actor, "admin.report.cancel_requested", settings.KafkaEventsTopic, "report", reportId, entity.UserId, payload, http.RequestAborted);
        await db.SaveChangesAsync(http.RequestAborted);
        await cache.DeleteAsync($"dashboard:{actor.Tenant}", $"summary:{actor.Tenant}");
        return ApiEnvelope.Ok(new { entity.ReportId, entity.Status }, "report cancel requested", http);
    }

    private static async Task<IResult> ReportCommandAsync(string reportId, DecisionRequest request, string eventType, string newStatus, string message, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AuditService audit, AdminCache cache, bool softDelete = false)
    {
        var actor = Actor(http, settings);
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminReportProjections.FirstOrDefaultAsync(x => x.Tenant == actor.Tenant && x.ReportId == reportId && x.DeletedAt == null, http.RequestAborted);
        if (entity is null) return ApiEnvelope.NotFound("report projection not found", http);
        entity.Status = newStatus;
        entity.UpdatedAt = DateTimeOffset.UtcNow;
        if (softDelete) entity.DeletedAt = DateTimeOffset.UtcNow;
        var payload = new { report_id = entity.ReportId, target_user_id = entity.UserId, status = entity.Status, requested_by = actor.UserId, reason = request.Reason ?? string.Empty };
        await audit.RecordAsync(db, http, actor, eventType, settings.KafkaEventsTopic, "report", reportId, entity.UserId, payload, http.RequestAborted);
        await db.SaveChangesAsync(http.RequestAborted);
        await cache.DeleteAsync($"dashboard:{actor.Tenant}", $"summary:{actor.Tenant}");
        return ApiEnvelope.Ok(new { entity.ReportId, entity.Status }, message, http);
    }

    private static async Task<IResult> ListAuditAsync(HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var query = db.AdminAuditEvents.AsNoTracking().Where(x => x.Tenant == tenant).OrderByDescending(x => x.CreatedAt);
        return ApiEnvelope.Ok(await PageAsync(query, http), "admin audit events loaded", http);
    }

    private static async Task<IResult> GetAuditAsync(string eventId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        var entity = await db.AdminAuditEvents.AsNoTracking().FirstOrDefaultAsync(x => x.Tenant == tenant && x.EventId == eventId, http.RequestAborted);
        return entity is null ? ApiEnvelope.NotFound("admin audit event not found", http) : ApiEnvelope.Ok(entity, "admin audit event loaded", http);
    }

    private static async Task UpsertAdminProfileAndUserProjectionAsync(AdminDbContext db, AdminSettings settings, string tenant, AdminRegistrationRequest request, CancellationToken ct)
    {
        var profile = await db.AdminProfiles.FirstOrDefaultAsync(x => x.Tenant == tenant && x.AdminUserId == request.UserId, ct);
        if (profile is null)
        {
            db.AdminProfiles.Add(new AdminProfile
            {
                Tenant = tenant,
                AdminUserId = request.UserId,
                Username = request.Username,
                Email = request.Email,
                FullName = request.FullName,
                Role = "admin",
                AdminStatus = "approved",
                Status = "active",
                Source = settings.DefaultAdminSource
            });
        }
        else
        {
            profile.AdminStatus = "approved";
            profile.Status = "active";
        }

        var user = await db.AdminUserProjections.FirstOrDefaultAsync(x => x.Tenant == tenant && x.UserId == request.UserId, ct);
        if (user is null)
        {
            db.AdminUserProjections.Add(new AdminUserProjection
            {
                Tenant = tenant,
                UserId = request.UserId,
                Username = request.Username,
                Email = request.Email,
                FullName = request.FullName,
                Role = "admin",
                AdminStatus = "approved",
                Status = "active",
                Payload = JsonSerializer.Serialize(new { request.UserId, request.Username, request.Email, role = "admin", admin_status = "approved" }, JsonOptionsFactory.Options)
            });
        }
        else
        {
            user.Role = "admin";
            user.AdminStatus = "approved";
            user.Status = "active";
        }
    }

    private static async Task<object> PageAsync<T>(IQueryable<T> query, HttpContext http)
    {
        var page = Page(http);
        var limit = Limit(http);
        var total = await query.CountAsync(http.RequestAborted);
        var items = await query.Skip((page - 1) * limit).Take(limit).ToListAsync(http.RequestAborted);
        return new { page, limit, total, items };
    }

    private static object PageList<T>(IReadOnlyList<T> source, HttpContext http)
    {
        var page = Page(http);
        var limit = Limit(http);
        var total = source.Count;
        var items = source.Skip((page - 1) * limit).Take(limit).ToList();
        return new { page, limit, total, items };
    }

    private static bool IsOverdueTodoProjection(AdminTodoProjection todo, DateTimeOffset now)
    {
        var status = (todo.Status ?? string.Empty).Trim().ToLowerInvariant();
        if (status is "completed" or "archived" or "cancelled" or "deleted" or "hard_deleted")
        {
            return false;
        }

        var dueAt = PayloadDate(todo.Payload, "due_date", "dueDate", "due_at", "dueAt");
        return dueAt.HasValue && dueAt.Value < now;
    }

    private static DateTimeOffset? PayloadDate(string payload, params string[] names)
    {
        try
        {
            using var document = JsonDocument.Parse(string.IsNullOrWhiteSpace(payload) ? "{}" : payload);
            return FindDate(document.RootElement, names);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static DateTimeOffset? FindDate(JsonElement element, params string[] names)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            foreach (var name in names)
            {
                if (element.TryGetProperty(name, out var direct))
                {
                    var parsed = CoerceDate(direct);
                    if (parsed.HasValue) return parsed;
                }
            }

            foreach (var property in element.EnumerateObject())
            {
                if (property.Value.ValueKind is JsonValueKind.Object or JsonValueKind.Array)
                {
                    var parsed = FindDate(property.Value, names);
                    if (parsed.HasValue) return parsed;
                }
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray())
            {
                var parsed = FindDate(item, names);
                if (parsed.HasValue) return parsed;
            }
        }

        return null;
    }

    private static DateTimeOffset? CoerceDate(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.String && DateTimeOffset.TryParse(value.GetString(), out var parsed))
        {
            return parsed;
        }

        if (value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var unixSeconds))
        {
            try
            {
                return DateTimeOffset.FromUnixTimeSeconds(unixSeconds);
            }
            catch (ArgumentOutOfRangeException)
            {
                return null;
            }
        }

        return null;
    }

    private static async Task<AdminUserProjection?> LoadUserAsync(string userId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        return await db.AdminUserProjections.AsNoTracking().FirstOrDefaultAsync(x => x.Tenant == tenant && x.UserId == userId && x.DeletedAt == null, http.RequestAborted);
    }

    private static async Task<AdminReportProjection?> LoadReportAsync(string reportId, HttpContext http, IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings)
    {
        var tenant = Actor(http, settings).Tenant;
        await using var db = await dbFactory.CreateDbContextAsync(http.RequestAborted);
        return await db.AdminReportProjections.AsNoTracking().FirstOrDefaultAsync(x => x.Tenant == tenant && x.ReportId == reportId && x.DeletedAt == null, http.RequestAborted);
    }

    private static object PayloadValue(string payload, string propertyName)
    {
        try
        {
            using var document = JsonDocument.Parse(string.IsNullOrWhiteSpace(payload) ? "{}" : payload);
            if (document.RootElement.ValueKind == JsonValueKind.Object && document.RootElement.TryGetProperty(propertyName, out var value))
            {
                return value.Clone();
            }
        }
        catch (JsonException)
        {
            // Stored projection payload was not JSON; return an empty object to preserve response envelope stability.
        }
        return new { };
    }

    private static IQueryable<T> ApplyStatus<T>(IQueryable<T> query, HttpContext http) where T : class
    {
        var status = http.Request.Query["status"].ToString();
        if (string.IsNullOrWhiteSpace(status)) return query;
        status = status.Trim().ToLowerInvariant();
        return query.Where(x => EF.Property<string>(x, "Status") == status);
    }

    private static int Page(HttpContext http) => int.TryParse(http.Request.Query["page"], out var page) && page > 0 ? page : 1;
    private static int Limit(HttpContext http) => int.TryParse(http.Request.Query["limit"], out var limit) && limit > 0 ? Math.Min(limit, 100) : 50;

    private static AdminActor Actor(HttpContext http, AdminSettings settings)
    {
        var actor = AdminActor.From(http);
        return string.IsNullOrWhiteSpace(actor.Tenant) ? actor with { Tenant = settings.Tenant } : actor;
    }
}