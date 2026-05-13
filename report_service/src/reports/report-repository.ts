import type { PoolClient } from "../persistence/postgres.js";
import type { PostgresDatabase } from "../persistence/postgres.js";
import type { ReportFormat } from "../storage/paths.js";
import type { ReportAuditRecord, ReportFileRecord, ReportJobStatus, ReportProgressRecord, ReportProgressStage, ReportRequestRecord, ReportScheduleRecord, ReportStatus, ReportTemplateRecord } from "./report-models.js";

export interface CreateReportInput {
  reportId: string;
  tenant: string;
  requesterUserId: string;
  targetUserId: string;
  reportType: string;
  format: ReportFormat;
  filters: Record<string, unknown>;
  options: Record<string, unknown>;
  dateFrom: string | null;
  dateTo: string | null;
  requestId: string;
  traceId: string;
  correlationId: string;
}

export interface CreateFileInput {
  reportId: string;
  tenant: string;
  format: ReportFormat;
  fileName: string;
  contentType: string;
  fileSizeBytes: number;
  s3Bucket: string;
  s3ObjectKey: string;
  checksumSha256: string;
  previewSupported: boolean;
}

export interface ListReportsInput {
  tenant: string;
  requesterUserId: string;
  targetUserId?: string;
  status?: ReportStatus;
  limit: number;
  offset: number;
}

export class ReportRepository {
  public constructor(private readonly db: PostgresDatabase) {}

  public async createReport(client: PoolClient, input: CreateReportInput): Promise<ReportRequestRecord> {
    const result = await client.query<ReportRequestRecord>(
      `insert into report.report_requests
        (report_id, tenant, requester_user_id, target_user_id, report_type, format, status, filters, options,
         date_from, date_to, queued_at, request_id, trace_id, correlation_id)
       values ($1,$2,$3,$4,$5,$6,'QUEUED',$7::jsonb,$8::jsonb,$9,$10,now(),$11,$12,$13)
       returning *`,
      [
        input.reportId,
        input.tenant,
        input.requesterUserId,
        input.targetUserId,
        input.reportType,
        input.format,
        JSON.stringify(input.filters),
        JSON.stringify(input.options),
        input.dateFrom,
        input.dateTo,
        input.requestId,
        input.traceId,
        input.correlationId
      ]
    );
    return result.rows[0]!;
  }

  public async insertGenerationJob(client: PoolClient, input: { jobId: string; reportId: string; tenant: string; queueName: string; status: ReportJobStatus }): Promise<void> {
    await client.query(
      `insert into report.report_generation_jobs (job_id, report_id, tenant, queue_name, status, progress_percent, progress_stage)
       values ($1,$2,$3,$4,$5,0,'queued')
       on conflict (job_id) do update set status=excluded.status, progress_percent=0, progress_stage='queued', updated_at=now(), deleted_at=null`,
      [input.jobId, input.reportId, input.tenant, input.queueName, input.status]
    );
  }

  public async getById(reportId: string, tenant: string): Promise<ReportRequestRecord | undefined> {
    const result = await this.db.query<ReportRequestRecord>(
      `select * from report.report_requests where report_id=$1 and tenant=$2 and deleted_at is null`,
      [reportId, tenant]
    );
    return result.rows[0];
  }

  public async list(input: ListReportsInput): Promise<ReportRequestRecord[]> {
    const params: unknown[] = [input.tenant, input.requesterUserId, input.limit, input.offset];
    const filters = ["tenant=$1", "requester_user_id=$2", "deleted_at is null"];
    let index = 5;
    if (input.targetUserId) {
      filters.push(`target_user_id=$${index++}`);
      params.push(input.targetUserId);
    }
    if (input.status) {
      filters.push(`status=$${index++}`);
      params.push(input.status);
    }
    const result = await this.db.query<ReportRequestRecord>(
      `select * from report.report_requests where ${filters.join(" and ")} order by created_at desc limit $3 offset $4`,
      params
    );
    return result.rows;
  }

  public async markStatus(
    client: PoolClient,
    reportId: string,
    tenant: string,
    status: ReportStatus,
    fields: { errorCode?: string | null; errorMessage?: string | null } = {}
  ): Promise<ReportRequestRecord | undefined> {
    const timestampColumn = status === "QUEUED" ? "queued_at" : status === "PROCESSING" ? "processing_started_at" : status === "COMPLETED" ? "completed_at" : status === "FAILED" ? "failed_at" : status === "CANCELLED" ? "cancelled_at" : status === "EXPIRED" ? "expired_at" : null;
    const setTimestamp = timestampColumn ? `, ${timestampColumn}=now()` : "";
    const result = await client.query<ReportRequestRecord>(
      `update report.report_requests
          set status=$3, error_code=$4, error_message=$5${setTimestamp}, updated_at=now(), deleted_at=case when $3='DELETED' then now() else deleted_at end
        where report_id=$1 and tenant=$2 and deleted_at is null
        returning *`,
      [reportId, tenant, status, fields.errorCode ?? null, fields.errorMessage ?? null]
    );
    return result.rows[0];
  }

  public async updateJobStatus(client: PoolClient, input: { reportId: string; tenant: string; status: ReportJobStatus; errorCode?: string | null; errorMessage?: string | null; durationMs?: number | null; progressPercent?: number; progressStage?: ReportProgressStage }): Promise<void> {
    const started = input.status === "PROCESSING" ? ", started_at=coalesce(started_at, now()), locked_at=now()" : "";
    const finished = ["COMPLETED", "FAILED", "CANCELLED"].includes(input.status) ? ", finished_at=now()" : "";
    await client.query(
      `update report.report_generation_jobs
          set status=$3, attempt_count=attempt_count + case when $3='PROCESSING' then 1 else 0 end,
              error_code=$4, error_message=$5, duration_ms=coalesce($6,duration_ms),
              progress_percent=coalesce($7, progress_percent), progress_stage=coalesce($8, progress_stage)${started}${finished}, updated_at=now()
        where report_id=$1 and tenant=$2`,
      [input.reportId, input.tenant, input.status, input.errorCode ?? null, input.errorMessage ?? null, input.durationMs ?? null, input.progressPercent ?? null, input.progressStage ?? null]
    );
  }

  public async insertProgress(client: PoolClient, input: { reportId: string; tenant: string; stage: ReportProgressStage; percent: number; message: string; payload?: Record<string, unknown> }): Promise<void> {
    await client.query(
      `insert into report.report_progress_events (report_id, tenant, stage, progress_percent, message, payload)
       values ($1,$2,$3,$4,$5,$6::jsonb)`,
      [input.reportId, input.tenant, input.stage, input.percent, input.message, JSON.stringify(input.payload ?? {})]
    );
  }

  public async getProgress(reportId: string, tenant: string): Promise<ReportProgressRecord | undefined> {
    const result = await this.db.query<ReportProgressRecord & { last_message: string | null }>(
      `select j.report_id, j.tenant, j.status, j.progress_percent, j.progress_stage, j.started_at, j.finished_at, j.duration_ms, j.error_code, j.error_message, j.updated_at,
              (select p.message from report.report_progress_events p where p.tenant=j.tenant and p.report_id=j.report_id order by p.created_at desc limit 1) as last_message
         from report.report_generation_jobs j
        where j.report_id=$1 and j.tenant=$2 and j.deleted_at is null
        order by j.created_at desc limit 1`,
      [reportId, tenant]
    );
    return result.rows[0];
  }

  public async listProgressEvents(reportId: string, tenant: string, limit = 100): Promise<Array<Record<string, unknown>>> {
    const result = await this.db.query(
      `select progress_id, report_id, stage, progress_percent, message, payload, created_at
         from report.report_progress_events
        where tenant=$1 and report_id=$2
        order by created_at desc
        limit $3`,
      [tenant, reportId, limit]
    );
    return result.rows;
  }

  public async insertFile(client: PoolClient, input: CreateFileInput): Promise<ReportFileRecord> {
    const result = await client.query<ReportFileRecord>(
      `insert into report.report_files
        (report_id, tenant, format, file_name, content_type, file_size_bytes, s3_bucket, s3_object_key, checksum_sha256, preview_supported)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
       on conflict (tenant, report_id, format) do update
          set file_name=excluded.file_name, content_type=excluded.content_type, file_size_bytes=excluded.file_size_bytes,
              s3_bucket=excluded.s3_bucket, s3_object_key=excluded.s3_object_key,
              checksum_sha256=excluded.checksum_sha256, preview_supported=excluded.preview_supported,
              updated_at=now(), deleted_at=null
       returning *`,
      [
        input.reportId,
        input.tenant,
        input.format,
        input.fileName,
        input.contentType,
        input.fileSizeBytes,
        input.s3Bucket,
        input.s3ObjectKey,
        input.checksumSha256,
        input.previewSupported
      ]
    );
    return result.rows[0]!;
  }

  public async getFile(reportId: string, tenant: string): Promise<ReportFileRecord | undefined> {
    const result = await this.db.query<ReportFileRecord>(
      `select * from report.report_files where report_id=$1 and tenant=$2 and deleted_at is null order by created_at desc limit 1`,
      [reportId, tenant]
    );
    return result.rows[0];
  }

  public async getFiles(reportId: string, tenant: string): Promise<ReportFileRecord[]> {
    const result = await this.db.query<ReportFileRecord>(
      `select * from report.report_files where report_id=$1 and tenant=$2 and deleted_at is null order by created_at desc`,
      [reportId, tenant]
    );
    return result.rows;
  }

  public async incrementDownloadCount(reportId: string, tenant: string): Promise<void> {
    await this.db.query(
      `update report.report_files set download_count=download_count+1, last_downloaded_at=now(), updated_at=now() where report_id=$1 and tenant=$2 and deleted_at is null`,
      [reportId, tenant]
    );
  }

  public async hasActiveGrant(input: { tenant: string; requesterUserId: string; targetUserId: string; scopes: string[] }): Promise<boolean> {
    const result = await this.db.query(
      `select 1
         from report.report_access_grant_projection
        where tenant=$1
          and requester_user_id=$2
          and target_user_id=$3
          and upper(status) in ('APPROVED','ACTIVE')
          and (expires_at is null or expires_at > now())
          and (scope = any($4::text[]) or scope='*')
          and deleted_at is null
        limit 1`,
      [input.tenant, input.requesterUserId, input.targetUserId, input.scopes]
    );
    return (result.rowCount ?? 0) > 0;
  }

  public async listTemplates(tenant: string): Promise<ReportTemplateRecord[]> {
    const result = await this.db.query<ReportTemplateRecord>(
      `select * from report.report_templates where tenant=$1 and deleted_at is null order by updated_at desc`,
      [tenant]
    );
    return result.rows;
  }

  public async getTemplate(tenant: string, templateId: string): Promise<ReportTemplateRecord | undefined> {
    const result = await this.db.query<ReportTemplateRecord>(
      `select * from report.report_templates where tenant=$1 and template_id=$2 and deleted_at is null`,
      [tenant, templateId]
    );
    return result.rows[0];
  }

  public async createTemplate(client: PoolClient, input: { templateId: string; tenant: string; reportType: string; name: string; description?: string | null; format: ReportFormat; templateContent: string; schema: Record<string, unknown>; style: Record<string, unknown>; createdBy: string }): Promise<ReportTemplateRecord> {
    const result = await client.query<ReportTemplateRecord>(
      `insert into report.report_templates (template_id, tenant, report_type, name, description, format, template_content, schema, style, created_by)
       values ($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9::jsonb,$10)
       returning *`,
      [input.templateId, input.tenant, input.reportType, input.name, input.description ?? null, input.format, input.templateContent, JSON.stringify(input.schema), JSON.stringify(input.style), input.createdBy]
    );
    return result.rows[0]!;
  }

  public async updateTemplate(client: PoolClient, tenant: string, templateId: string, patch: Partial<{ reportType: string; name: string; description: string | null; format: ReportFormat; templateContent: string; schema: Record<string, unknown>; style: Record<string, unknown> }>): Promise<ReportTemplateRecord | undefined> {
    const current = await this.getTemplate(tenant, templateId);
    if (!current) return undefined;
    const result = await client.query<ReportTemplateRecord>(
      `update report.report_templates
          set report_type=$3, name=$4, description=$5, format=$6, template_content=$7, schema=$8::jsonb, style=$9::jsonb, version=version+1, updated_at=now()
        where tenant=$1 and template_id=$2 and deleted_at is null
        returning *`,
      [tenant, templateId, patch.reportType ?? current.report_type, patch.name ?? current.name, patch.description ?? current.description, patch.format ?? current.format, patch.templateContent ?? current.template_content, JSON.stringify(patch.schema ?? current.schema), JSON.stringify(patch.style ?? current.style)]
    );
    return result.rows[0];
  }

  public async setTemplateStatus(client: PoolClient, tenant: string, templateId: string, status: "ACTIVE" | "INACTIVE"): Promise<ReportTemplateRecord | undefined> {
    const result = await client.query<ReportTemplateRecord>(
      `update report.report_templates set status=$3, updated_at=now() where tenant=$1 and template_id=$2 and deleted_at is null returning *`,
      [tenant, templateId, status]
    );
    return result.rows[0];
  }

  public async listSchedules(tenant: string, ownerUserId: string, includeAll: boolean): Promise<ReportScheduleRecord[]> {
    const params: unknown[] = [tenant];
    const filters = ["tenant=$1", "deleted_at is null"];
    if (!includeAll) {
      params.push(ownerUserId);
      filters.push(`owner_user_id=$${params.length}`);
    }
    const result = await this.db.query<ReportScheduleRecord>(
      `select * from report.report_schedules where ${filters.join(" and ")} order by created_at desc`,
      params
    );
    return result.rows;
  }

  public async getSchedule(tenant: string, scheduleId: string): Promise<ReportScheduleRecord | undefined> {
    const result = await this.db.query<ReportScheduleRecord>(
      `select * from report.report_schedules where tenant=$1 and schedule_id=$2 and deleted_at is null`,
      [tenant, scheduleId]
    );
    return result.rows[0];
  }

  public async createSchedule(client: PoolClient, input: { scheduleId: string; tenant: string; ownerUserId: string; targetUserId: string; reportType: string; format: ReportFormat; cronExpression: string; timezone: string; filters: Record<string, unknown>; options: Record<string, unknown> }): Promise<ReportScheduleRecord> {
    const result = await client.query<ReportScheduleRecord>(
      `insert into report.report_schedules (schedule_id, tenant, owner_user_id, target_user_id, report_type, format, cron_expression, timezone, filters, options, status)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10::jsonb,'ACTIVE')
       returning *`,
      [input.scheduleId, input.tenant, input.ownerUserId, input.targetUserId, input.reportType, input.format, input.cronExpression, input.timezone, JSON.stringify(input.filters), JSON.stringify(input.options)]
    );
    return result.rows[0]!;
  }

  public async updateSchedule(client: PoolClient, tenant: string, scheduleId: string, patch: Partial<{ targetUserId: string; reportType: string; format: ReportFormat; cronExpression: string; timezone: string; filters: Record<string, unknown>; options: Record<string, unknown> }>): Promise<ReportScheduleRecord | undefined> {
    const current = await this.getSchedule(tenant, scheduleId);
    if (!current) return undefined;
    const result = await client.query<ReportScheduleRecord>(
      `update report.report_schedules
          set target_user_id=$3, report_type=$4, format=$5, cron_expression=$6, timezone=$7, filters=$8::jsonb, options=$9::jsonb, updated_at=now()
        where tenant=$1 and schedule_id=$2 and deleted_at is null
        returning *`,
      [tenant, scheduleId, patch.targetUserId ?? current.target_user_id, patch.reportType ?? current.report_type, patch.format ?? current.format, patch.cronExpression ?? current.cron_expression, patch.timezone ?? current.timezone, JSON.stringify(patch.filters ?? current.filters), JSON.stringify(patch.options ?? current.options)]
    );
    return result.rows[0];
  }

  public async setScheduleStatus(client: PoolClient, tenant: string, scheduleId: string, status: "ACTIVE" | "PAUSED" | "DELETED"): Promise<ReportScheduleRecord | undefined> {
    const result = await client.query<ReportScheduleRecord>(
      `update report.report_schedules set status=$3, updated_at=now(), deleted_at=case when $3='DELETED' then now() else deleted_at end where tenant=$1 and schedule_id=$2 and deleted_at is null returning *`,
      [tenant, scheduleId, status]
    );
    return result.rows[0];
  }

  public async listAudit(tenant: string, limit: number, offset: number): Promise<ReportAuditRecord[]> {
    const result = await this.db.query<ReportAuditRecord>(
      `select event_id, event_type, report_id, actor_id, target_user_id, s3_bucket, s3_object_key, payload, created_at
         from report.report_audit_events
        where tenant=$1 and deleted_at is null
        order by created_at desc limit $2 offset $3`,
      [tenant, limit, offset]
    );
    return result.rows;
  }

  public async getAudit(tenant: string, eventId: string): Promise<ReportAuditRecord | undefined> {
    const result = await this.db.query<ReportAuditRecord>(
      `select event_id, event_type, report_id, actor_id, target_user_id, s3_bucket, s3_object_key, payload, created_at
         from report.report_audit_events
        where tenant=$1 and event_id=$2 and deleted_at is null`,
      [tenant, eventId]
    );
    return result.rows[0];
  }
}
