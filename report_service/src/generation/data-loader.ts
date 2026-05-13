import type { AppConfig } from "../config/config.js";
import type { PostgresDatabase } from "../persistence/postgres.js";
import { getReportType } from "../report-types/registry.js";

export interface ReportRequestForGeneration {
  report_id: string;
  tenant: string;
  requester_user_id: string;
  target_user_id: string;
  report_type: string;
  format: string;
  filters: Record<string, unknown>;
  options: Record<string, unknown>;
  date_from: string | null;
  date_to: string | null;
}

export type Dataset = Record<string, unknown>[];
export type ReportDatasets = Record<string, Dataset>;

const SECRET_KEYS = /password|password_hash|access_token|refresh_token|authorization|jwt|secret|access_key|secret_key|connection|string|cookie|session/i;

function redactRow(row: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(row).map(([key, value]) => {
      if (SECRET_KEYS.test(key)) return [key, "[REDACTED]"];
      if (value && typeof value === "object" && !Array.isArray(value)) return [key, redactRow(value as Record<string, unknown>)];
      return [key, value];
    })
  );
}

function countBy(rows: Dataset, key: string): Dataset {
  const counts = new Map<string, number>();
  for (const row of rows) {
    const value = String(row[key] ?? "unknown");
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  return [...counts.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([value, count]) => ({ [key]: value, count }));
}

function activityByDay(rows: Dataset): Dataset {
  const counts = new Map<string, number>();
  for (const row of rows) {
    const raw = row.occurred_at ?? row.created_at ?? row.updated_at;
    const day = raw ? String(raw).slice(0, 10) : "unknown";
    counts.set(day, (counts.get(day) ?? 0) + 1);
  }
  return [...counts.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([date, count]) => ({ date, count }));
}

export class ReportDataLoader {
  public constructor(private readonly db: PostgresDatabase, private readonly config: AppConfig) {}

  public async load(report: ReportRequestForGeneration): Promise<ReportDatasets> {
    const definition = getReportType(report.report_type);
    const datasets: ReportDatasets = {};

    if (!definition) return { warnings: [{ message: "Unsupported report type at generation time", report_type: report.report_type }] };

    for (const projection of definition.source_projections) {
      if (projection === "report_user_projection") datasets.user = await this.loadUser(report);
      if (projection === "report_calculation_projection") datasets.calculations = await this.loadCalculations(report);
      if (projection === "report_todo_projection") datasets.todos = await this.loadTodos(report);
      if (projection === "report_activity_projection") datasets.activity = await this.loadActivity(report);
      if (projection === "report_access_grant_projection") datasets.access_grants = await this.loadAccessGrants(report);
      if (projection === "report_admin_decision_projection") datasets.admin_decisions = await this.loadAdminDecisions(report);
      if (projection === "report_audit_events") datasets.audit_events = await this.loadAuditEvents(report);
      if (projection === "report_requests") datasets.report_requests = await this.loadReportRequests(report);
      if (projection === "report_files") datasets.report_files = await this.loadReportFiles(report);
      if (projection === "report_generation_jobs") datasets.generation_jobs = await this.loadGenerationJobs(report);
      if (projection === "report_progress_events") datasets.progress_events = await this.loadProgressEvents(report);
    }

    const primaryRows = Object.entries(datasets).filter(([name]) => name !== "summary").flatMap(([, rows]) => rows);
    datasets.summary = this.buildSummary(datasets, primaryRows);
    if (primaryRows.length === 0) datasets.warnings = [{ message: "No projection rows matched the report request. The report is valid but empty." }];
    return datasets;
  }

  private async loadUser(report: ReportRequestForGeneration): Promise<Dataset> {
    const result = await this.db.query(
      `select user_id, username, email, role, admin_status, status, payload, updated_at, created_at
         from report.report_user_projection
        where tenant=$1 and user_id=$2 and deleted_at is null
        limit 1`,
      [report.tenant, report.target_user_id]
    );
    return result.rows.map(redactRow);
  }

  private async loadCalculations(report: ReportRequestForGeneration): Promise<Dataset> {
    const params: unknown[] = [report.tenant, report.target_user_id, this.limit(report)];
    const filters: string[] = ["tenant=$1", "user_id=$2", "deleted_at is null"];
    let index = 4;
    if (report.date_from) { filters.push(`occurred_at::date >= $${index++}`); params.push(report.date_from); }
    if (report.date_to) { filters.push(`occurred_at::date <= $${index++}`); params.push(report.date_to); }
    if (typeof report.filters.operation === "string") { filters.push(`operation = $${index++}`); params.push(report.filters.operation); }
    if (typeof report.filters.status === "string") { filters.push(`status = $${index++}`); params.push(report.filters.status); }
    const result = await this.db.query(
      `select calculation_id, user_id, operation, status, payload, occurred_at, updated_at, created_at
         from report.report_calculation_projection
        where ${filters.join(" and ")}
        order by coalesce(occurred_at, updated_at, created_at) desc
        limit $3`,
      params
    );
    return result.rows.map(redactRow);
  }

  private async loadTodos(report: ReportRequestForGeneration): Promise<Dataset> {
    const params: unknown[] = [report.tenant, report.target_user_id, this.limit(report)];
    const filters: string[] = ["tenant=$1", "user_id=$2", "deleted_at is null"];
    let index = 4;
    if (report.date_from) { filters.push(`occurred_at::date >= $${index++}`); params.push(report.date_from); }
    if (report.date_to) { filters.push(`occurred_at::date <= $${index++}`); params.push(report.date_to); }
    if (typeof report.filters.status === "string") { filters.push(`status = $${index++}`); params.push(report.filters.status); }
    if (typeof report.filters.priority === "string") { filters.push(`priority = $${index++}`); params.push(report.filters.priority); }
    const result = await this.db.query(
      `select todo_id, user_id, status, priority, payload, occurred_at, updated_at, created_at
         from report.report_todo_projection
        where ${filters.join(" and ")}
        order by coalesce(occurred_at, updated_at, created_at) desc
        limit $3`,
      params
    );
    return result.rows.map(redactRow);
  }

  private async loadActivity(report: ReportRequestForGeneration): Promise<Dataset> {
    const params: unknown[] = [report.tenant, report.target_user_id, this.limit(report)];
    const filters: string[] = ["tenant=$1", "user_id=$2", "deleted_at is null"];
    let index = 4;
    if (report.date_from) { filters.push(`occurred_at::date >= $${index++}`); params.push(report.date_from); }
    if (report.date_to) { filters.push(`occurred_at::date <= $${index++}`); params.push(report.date_to); }
    if (typeof report.filters.activity_type === "string") { filters.push(`activity_type = $${index++}`); params.push(report.filters.activity_type); }
    if (typeof report.filters.source_service === "string") { filters.push(`source_service = $${index++}`); params.push(report.filters.source_service); }
    const result = await this.db.query(
      `select activity_id, user_id, activity_type, source_service, payload, occurred_at, updated_at, created_at
         from report.report_activity_projection
        where ${filters.join(" and ")}
        order by coalesce(occurred_at, updated_at, created_at) desc
        limit $3`,
      params
    );
    return result.rows.map(redactRow);
  }

  private async loadAccessGrants(report: ReportRequestForGeneration): Promise<Dataset> {
    const params: unknown[] = [report.tenant, report.target_user_id, this.limit(report)];
    const filters = ["tenant=$1", "(target_user_id=$2 or requester_user_id=$2)", "deleted_at is null"];
    let index = 4;
    if (typeof report.filters.status === "string") { filters.push(`status = $${index++}`); params.push(report.filters.status); }
    if (typeof report.filters.scope === "string") { filters.push(`scope = $${index++}`); params.push(report.filters.scope); }
    const result = await this.db.query(
      `select grant_id, requester_user_id, target_user_id, scope, status, granted_at, revoked_at, expires_at, payload, updated_at, created_at
         from report.report_access_grant_projection
        where ${filters.join(" and ")}
        order by updated_at desc
        limit $3`,
      params
    );
    return result.rows.map(redactRow);
  }

  private async loadAdminDecisions(report: ReportRequestForGeneration): Promise<Dataset> {
    const params: unknown[] = [report.tenant, report.target_user_id, this.limit(report)];
    const filters = ["tenant=$1", "(target_user_id=$2 or actor_id=$2)", "deleted_at is null"];
    let index = 4;
    if (typeof report.filters.decision === "string") { filters.push(`decision = $${index++}`); params.push(report.filters.decision); }
    const result = await this.db.query(
      `select decision_id, actor_id, target_user_id, decision, payload, occurred_at, updated_at, created_at
         from report.report_admin_decision_projection
        where ${filters.join(" and ")}
        order by coalesce(occurred_at, updated_at, created_at) desc
        limit $3`,
      params
    );
    return result.rows.map(redactRow);
  }

  private async loadAuditEvents(report: ReportRequestForGeneration): Promise<Dataset> {
    const params: unknown[] = [report.tenant, this.limit(report)];
    const filters = ["tenant=$1", "deleted_at is null"];
    let index = 3;
    if (typeof report.filters.event_type === "string") { filters.push(`event_type = $${index++}`); params.push(report.filters.event_type); }
    const result = await this.db.query(
      `select event_id, event_type, report_id, actor_id, target_user_id, s3_bucket, s3_object_key, payload, created_at
         from report.report_audit_events
        where ${filters.join(" and ")}
        order by created_at desc
        limit $2`,
      params
    );
    return result.rows.map(redactRow);
  }

  private async loadReportRequests(report: ReportRequestForGeneration): Promise<Dataset> {
    const result = await this.db.query(
      `select report_id, requester_user_id, target_user_id, report_type, format, status, error_code, requested_at, completed_at, failed_at, created_at, updated_at
         from report.report_requests
        where tenant=$1 and deleted_at is null
        order by created_at desc
        limit $2`,
      [report.tenant, this.limit(report)]
    );
    return result.rows.map(redactRow);
  }

  private async loadReportFiles(report: ReportRequestForGeneration): Promise<Dataset> {
    const result = await this.db.query(
      `select file_id, report_id, format, file_name, content_type, file_size_bytes, s3_bucket, s3_object_key, checksum_sha256, preview_supported, download_count, created_at
         from report.report_files
        where tenant=$1 and deleted_at is null
        order by created_at desc
        limit $2`,
      [report.tenant, this.limit(report)]
    );
    return result.rows.map(redactRow);
  }

  private async loadGenerationJobs(report: ReportRequestForGeneration): Promise<Dataset> {
    const result = await this.db.query(
      `select job_id, report_id, queue_name, status, attempt_count, max_attempts, progress_percent, progress_stage, started_at, finished_at, duration_ms, error_code, error_message, created_at, updated_at
         from report.report_generation_jobs
        where tenant=$1 and deleted_at is null
        order by updated_at desc
        limit $2`,
      [report.tenant, this.limit(report)]
    );
    return result.rows.map(redactRow);
  }

  private async loadProgressEvents(report: ReportRequestForGeneration): Promise<Dataset> {
    const result = await this.db.query(
      `select progress_id, report_id, stage, progress_percent, message, payload, created_at
         from report.report_progress_events
        where tenant=$1
        order by created_at desc
        limit $2`,
      [report.tenant, this.limit(report)]
    );
    return result.rows.map(redactRow);
  }

  private buildSummary(datasets: ReportDatasets, primaryRows: Dataset): Dataset {
    const summary: Dataset = [
      { metric: "dataset_count", value: Object.keys(datasets).length },
      { metric: "total_rows", value: primaryRows.length }
    ];
    for (const [name, rows] of Object.entries(datasets)) summary.push({ metric: `${name}_rows`, value: rows.length });
    summary.push(...countBy(primaryRows, "status").map((row) => ({ metric: "status_breakdown", ...row })));
    summary.push(...countBy(primaryRows, "priority").map((row) => ({ metric: "priority_breakdown", ...row })));
    summary.push(...countBy(primaryRows, "source_service").map((row) => ({ metric: "source_service_breakdown", ...row })));
    summary.push(...countBy(primaryRows, "operation").map((row) => ({ metric: "operation_breakdown", ...row })));
    summary.push(...activityByDay(primaryRows).map((row) => ({ metric: "activity_by_day", ...row })));
    return summary.filter((row) => !Object.values(row).includes("unknown") || row.metric === "total_rows");
  }

  private limit(report: ReportRequestForGeneration): number {
    const requested = typeof report.options.limit === "number" ? report.options.limit : this.config.report.generationMaxRows;
    return Math.min(Math.max(Math.trunc(requested), 1), this.config.report.generationMaxRows);
  }
}
