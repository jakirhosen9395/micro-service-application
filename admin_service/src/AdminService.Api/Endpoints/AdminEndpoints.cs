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
        group.MapGet("/users/{userId}/access-grants", GetUserAccessGrantsAsync);
        group.MapGet("/users/{userId}/reports", GetUserReportsAsync);
        group.MapPost("/users/{userId}/suspend", SuspendUserAsync);
        group.MapPost("/users/{userId}/activate", ActivateUserAsync);
        group.MapPost("/users/{userId}/force-password-reset", ForcePasswordResetAsync);

        group.MapGet("/calculations", ListCalculationsAsync);
        group.MapGet("/calculations/summary", CalculationSummaryAsync);
        group.MapGet("/calculations/{calculationId}", GetCalculationAsync);
        group.MapGet("/calculations/users/{userId}", GetUserCalculationsAsync);

        group.MapGet("/todos", ListTodosAsync);
        group.MapGet("/todos/summary", TodoSummaryAsync);
        group.MapGet("/todos/{todoId}", GetTodoAsync);
        group.MapGet("/todos/users/{userId}", GetUserTodosAsync);

        group.MapPost("/reports", RequestReportAsync);
        group.MapGet("/reports", ListReportsAsync);
        group.MapGet("/reports/summary", ReportSummaryAsync);
        group.MapGet("/reports/{reportId}", GetReportAsync);
        group.MapGet("/reports/users/{userId}", GetUserReportsProjectionAsync);
        group.MapPost("/reports/{reportId}/cancel", CancelReportAsync);

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
