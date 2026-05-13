import type { ReportFormat } from "../storage/paths.js";

export type OwnerAccessPolicy = "self_or_grant_or_admin" | "admin_or_service" | "service_only";

export interface ReportTypeDefinition {
  report_type: string;
  name: string;
  description: string;
  allowed_formats: ReportFormat[];
  default_format: ReportFormat;
  source_projections: string[];
  filters_schema: Record<string, unknown>;
  options_schema: Record<string, unknown>;
  required_scopes: string[];
  owner_access_policy: OwnerAccessPolicy;
  default_sort: string;
  max_rows: number;
  preview_supported_formats: ReportFormat[];
}

const ALL_FORMATS: ReportFormat[] = ["pdf", "xlsx", "csv", "json", "html"];
const TEXT_PREVIEW: ReportFormat[] = ["json", "csv", "html"];

function def(input: Omit<ReportTypeDefinition, "allowed_formats" | "default_format" | "preview_supported_formats" | "max_rows"> & Partial<Pick<ReportTypeDefinition, "allowed_formats" | "default_format" | "preview_supported_formats" | "max_rows">>): ReportTypeDefinition {
  return {
    allowed_formats: input.allowed_formats ?? ALL_FORMATS,
    default_format: input.default_format ?? "pdf",
    preview_supported_formats: input.preview_supported_formats ?? TEXT_PREVIEW,
    max_rows: input.max_rows ?? 100000,
    ...input
  };
}

export const REPORT_TYPES: ReportTypeDefinition[] = [
  def({
    report_type: "calculator_history_report",
    name: "Calculator history report",
    description: "Calculation history loaded from report_calculation_projection for a user and optional date range.",
    source_projections: ["report_calculation_projection", "report_user_projection"],
    filters_schema: { operation: "optional string", status: "optional string" },
    options_schema: { include_summary: "optional boolean", include_raw_data: "optional boolean", timezone: "optional string", locale: "optional string", title: "optional string" },
    required_scopes: ["report:create", "calculator:history:read"],
    owner_access_policy: "self_or_grant_or_admin",
    default_sort: "occurred_at desc"
  }),
  def({
    report_type: "todo_summary_report",
    name: "Todo summary report",
    description: "Todo projection report with status and priority breakdowns.",
    source_projections: ["report_todo_projection", "report_user_projection"],
    filters_schema: { status: "optional string", priority: "optional string" },
    options_schema: { include_summary: "optional boolean", include_raw_data: "optional boolean" },
    required_scopes: ["report:create", "todo:read"],
    owner_access_policy: "self_or_grant_or_admin",
    default_sort: "occurred_at desc"
  }),
  def({
    report_type: "user_activity_report",
    name: "User activity report",
    description: "Activity timeline loaded from report_activity_projection.",
    source_projections: ["report_activity_projection", "report_user_projection"],
    filters_schema: { activity_type: "optional string", source_service: "optional string" },
    options_schema: { group_by_day: "optional boolean", include_summary: "optional boolean" },
    required_scopes: ["report:create", "user:activity:read"],
    owner_access_policy: "self_or_grant_or_admin",
    default_sort: "occurred_at desc"
  }),
  def({
    report_type: "full_user_report",
    name: "Full user report",
    description: "Combined profile, calculator, todo, access, decision, and activity projections.",
    source_projections: ["report_user_projection", "report_calculation_projection", "report_todo_projection", "report_access_grant_projection", "report_admin_decision_projection", "report_activity_projection"],
    filters_schema: { source_service: "optional string", status: "optional string" },
    options_schema: { include_sections: "optional string array", include_summary: "optional boolean" },
    required_scopes: ["report:create", "calculator:history:read", "todo:read", "user:activity:read"],
    owner_access_policy: "self_or_grant_or_admin",
    default_sort: "updated_at desc"
  }),
  def({
    report_type: "user_profile_report",
    name: "User profile report",
    description: "Safe user identity/profile projection without credentials or secrets.",
    source_projections: ["report_user_projection"],
    filters_schema: { role: "optional string", status: "optional string" },
    options_schema: { include_summary: "optional boolean" },
    required_scopes: ["report:create", "user:activity:read"],
    owner_access_policy: "self_or_grant_or_admin",
    default_sort: "updated_at desc"
  }),
  def({
    report_type: "user_dashboard_report",
    name: "User dashboard report",
    description: "Dashboard-style combined report for profile, calculations, todos, reports, and activity.",
    source_projections: ["report_user_projection", "report_calculation_projection", "report_todo_projection", "report_activity_projection"],
    filters_schema: { source_service: "optional string" },
    options_schema: { include_charts: "optional boolean", include_summary: "optional boolean" },
    required_scopes: ["report:create", "user:activity:read"],
    owner_access_policy: "self_or_grant_or_admin",
    default_sort: "updated_at desc"
  }),
  def({
    report_type: "user_access_grants_report",
    name: "User access grants report",
    description: "Access grant projection report for requester/target user relationships.",
    source_projections: ["report_access_grant_projection"],
    filters_schema: { status: "optional string", scope: "optional string" },
    options_schema: { include_expired: "optional boolean" },
    required_scopes: ["report:create"],
    owner_access_policy: "self_or_grant_or_admin",
    default_sort: "updated_at desc"
  }),
  def({
    report_type: "cross_user_access_report",
    name: "Cross-user access report",
    description: "Cross-user access grants and revocations for support and audit flows.",
    source_projections: ["report_access_grant_projection", "report_admin_decision_projection"],
    filters_schema: { status: "optional string", scope: "optional string" },
    options_schema: { include_revoked: "optional boolean" },
    required_scopes: ["report:create"],
    owner_access_policy: "admin_or_service",
    default_sort: "updated_at desc"
  }),
  def({
    report_type: "admin_decision_report",
    name: "Admin decision report",
    description: "Admin approval/rejection decision projection report.",
    source_projections: ["report_admin_decision_projection"],
    filters_schema: { decision: "optional string" },
    options_schema: { include_payload: "optional boolean" },
    required_scopes: ["report:create", "admin:audit:read"],
    owner_access_policy: "admin_or_service",
    default_sort: "occurred_at desc"
  }),
  def({
    report_type: "admin_audit_report",
    name: "Admin audit report",
    description: "Admin-facing report events and admin decision summaries.",
    source_projections: ["report_admin_decision_projection", "report_audit_events"],
    filters_schema: { event_type: "optional string", decision: "optional string" },
    options_schema: { include_payload: "optional boolean" },
    required_scopes: ["report:create", "admin:audit:read"],
    owner_access_policy: "admin_or_service",
    default_sort: "created_at desc"
  }),
  def({
    report_type: "calculator_summary_report",
    name: "Calculator summary report",
    description: "Summary-only calculation breakdown by operation and status.",
    source_projections: ["report_calculation_projection"],
    filters_schema: { operation: "optional string", status: "optional string" },
    options_schema: { include_raw_data: "optional boolean" },
    required_scopes: ["report:create", "calculator:history:read"],
    owner_access_policy: "self_or_grant_or_admin",
    default_sort: "occurred_at desc"
  }),
  def({
    report_type: "calculator_operations_report",
    name: "Calculator operations report",
    description: "Operation distribution and recent calculator activity.",
    source_projections: ["report_calculation_projection"],
    filters_schema: { operation: "optional string" },
    options_schema: { include_summary: "optional boolean" },
    required_scopes: ["report:create", "calculator:history:read"],
    owner_access_policy: "self_or_grant_or_admin",
    default_sort: "operation asc"
  }),
  def({
    report_type: "todo_activity_report",
    name: "Todo activity report",
    description: "Todo lifecycle activity report with status and priority details.",
    source_projections: ["report_todo_projection", "report_activity_projection"],
    filters_schema: { status: "optional string", priority: "optional string", activity_type: "optional string" },
    options_schema: { include_summary: "optional boolean" },
    required_scopes: ["report:create", "todo:read", "todo:history:read"],
    owner_access_policy: "self_or_grant_or_admin",
    default_sort: "occurred_at desc"
  }),
  def({
    report_type: "todo_status_report",
    name: "Todo status report",
    description: "Todo status report grouped by status and priority.",
    source_projections: ["report_todo_projection"],
    filters_schema: { status: "optional string", priority: "optional string" },
    options_schema: { include_raw_data: "optional boolean" },
    required_scopes: ["report:create", "todo:read"],
    owner_access_policy: "self_or_grant_or_admin",
    default_sort: "status asc"
  }),
  def({
    report_type: "productivity_summary_report",
    name: "Productivity summary report",
    description: "Combined calculator/todo/activity productivity summary.",
    source_projections: ["report_calculation_projection", "report_todo_projection", "report_activity_projection"],
    filters_schema: { source_service: "optional string" },
    options_schema: { include_charts: "optional boolean", include_summary: "optional boolean" },
    required_scopes: ["report:create", "calculator:history:read", "todo:read", "user:activity:read"],
    owner_access_policy: "self_or_grant_or_admin",
    default_sort: "occurred_at desc"
  }),
  def({
    report_type: "full_application_activity_report",
    name: "Full application activity report",
    description: "Cross-domain application activity report for approved admins and service actors.",
    source_projections: ["report_activity_projection", "report_calculation_projection", "report_todo_projection", "report_audit_events"],
    filters_schema: { source_service: "optional string", event_type: "optional string" },
    options_schema: { include_summary: "optional boolean", include_raw_data: "optional boolean" },
    required_scopes: ["report:create", "admin:audit:read"],
    owner_access_policy: "admin_or_service",
    default_sort: "created_at desc"
  }),
  def({
    report_type: "report_inventory_report",
    name: "Report inventory report",
    description: "Inventory of report requests and files owned by the report service.",
    source_projections: ["report_requests", "report_files"],
    filters_schema: { status: "optional string", format: "optional string" },
    options_schema: { include_files: "optional boolean" },
    required_scopes: ["report:create", "report:read"],
    owner_access_policy: "admin_or_service",
    default_sort: "created_at desc"
  }),
  def({
    report_type: "report_generation_health_report",
    name: "Report generation health report",
    description: "Report generation jobs, progress, and failures for queue observability.",
    source_projections: ["report_generation_jobs", "report_progress_events"],
    filters_schema: { status: "optional string", progress_stage: "optional string" },
    options_schema: { include_errors: "optional boolean" },
    required_scopes: ["report:create", "report:read"],
    owner_access_policy: "admin_or_service",
    default_sort: "updated_at desc"
  })
];

export function listReportTypes(): ReportTypeDefinition[] {
  return REPORT_TYPES;
}

export function getReportType(reportType: string): ReportTypeDefinition | undefined {
  return REPORT_TYPES.find((definition) => definition.report_type === reportType);
}
