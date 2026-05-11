using System.Text.Json;

namespace AdminService.Api.Contracts;

public sealed record DecisionRequest(string? Reason);

public sealed record AccessApprovalRequest(string? Scope, DateTimeOffset? ExpiresAt, string? Reason);

public sealed record AdminReportRequest(
    string ReportType,
    string? TargetUserId,
    string Format,
    DateOnly? DateFrom,
    DateOnly? DateTo,
    JsonElement? Filters,
    JsonElement? Options);
