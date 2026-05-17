import { randomUUID } from "node:crypto";
import type { FastifyRequest } from "fastify";
import type { AppConfig } from "../config/config.js";
import { createEventEnvelope, type EventEnvelope } from "../events/envelope.js";
import { Errors } from "../http/errors.js";
import type { AppLogger } from "../logging/logger.js";
import type { AuthenticatedUser } from "../types/auth.js";
import type { PostgresDatabase } from "../persistence/postgres.js";
import { insertOutboxEvent } from "../persistence/outbox.js";
import type { ReportQueue } from "../queue/report-queue.js";
import type { RedisCache } from "../cache/redis.js";
import { getReportType, listReportTypes } from "../report-types/registry.js";
import type { ReportFormat } from "../storage/paths.js";
import { reportFileKey } from "../storage/paths.js";
import type { S3Storage } from "../storage/s3.js";
import type { AuditService } from "../storage/audit-service.js";
import { ReportDataLoader, type ReportRequestForGeneration } from "../generation/data-loader.js";
import { renderReport } from "../generation/renderers.js";
import { ReportRepository } from "./report-repository.js";
import type { CreateReportRequest, CreateScheduleRequest, CreateTemplateRequest, ListReportsQuery, UpdateScheduleRequest, UpdateTemplateRequest } from "./report-schemas.js";
import type { ReportProgressStage, ReportRequestRecord } from "./report-models.js";

function publicReport(record: ReportRequestRecord): Record<string, unknown> {
  return {
    report_id: record.report_id,
    tenant: record.tenant,
    requester_user_id: record.requester_user_id,
    target_user_id: record.target_user_id,
    report_type: record.report_type,
    format: record.format,
    status: record.status,
    filters: record.filters,
    options: record.options,
    date_from: record.date_from,
    date_to: record.date_to,
    requested_at: record.requested_at,
    queued_at: record.queued_at,
    processing_started_at: record.processing_started_at,
    completed_at: record.completed_at,
    failed_at: record.failed_at,
    cancelled_at: record.cancelled_at,
    expired_at: record.expired_at,
    error_code: record.error_code,
    error_message: record.error_message,
    created_at: record.created_at,
    updated_at: record.updated_at
  };
}

function requestUserAgent(request: FastifyRequest): string | undefined {
  const value = request.headers["user-agent"];
  return Array.isArray(value) ? value[0] : value;
}

function isPrivileged(user: AuthenticatedUser): boolean {
  return user.role === "service" || user.role === "system" || (user.role === "admin" && user.admin_status === "approved");
}

function safeFileName(value: string): string {
  return value.replace(/[^a-zA-Z0-9_.-]/g, "_");
}

export class ReportService {
  private readonly repository: ReportRepository;
  private readonly dataLoader: ReportDataLoader;

  public constructor(
    private readonly config: AppConfig,
    private readonly db: PostgresDatabase,
    private readonly queue: ReportQueue,
    private readonly cache: RedisCache,
    private readonly s3: S3Storage,
    private readonly audit: AuditService,
    private readonly logger: AppLogger
  ) {
    this.repository = new ReportRepository(db);
    this.dataLoader = new ReportDataLoader(db, config);
  }

  public listTypes(): Record<string, unknown> {
    return { report_types: listReportTypes() };
  }

  public getType(reportType: string): Record<string, unknown> {
    const definition = getReportType(reportType);
    if (!definition) throw Errors.notFound("Report type not found", { report_type: reportType });
    return definition as unknown as Record<string, unknown>;
  }

  public async createReport(user: AuthenticatedUser, body: CreateReportRequest, request: FastifyRequest): Promise<Record<string, unknown>> {
    const definition = getReportType(body.report_type);
    if (!definition) throw Errors.validation("Unsupported report type", { error_code: "REPORT_TYPE_UNSUPPORTED", report_type: body.report_type });
    const format = body.format ?? definition.default_format;
    if (!definition.allowed_formats.includes(format)) {
      throw Errors.validation("Unsupported report format for report type", { error_code: "REPORT_FORMAT_UNSUPPORTED", report_type: body.report_type, format });
    }
    this.validateFilterKeys(body.filters, definition.filters_schema, body.report_type);

    const targetUserId = body.target_user_id ?? user.sub;
    if (definition.owner_access_policy === "admin_or_service" && !isPrivileged(user)) {
      throw Errors.forbidden("Report type requires approved admin, service, or system role", { report_type: body.report_type, error_code: "REPORT_ACCESS_DENIED" });
    }
    await this.assertTargetAccess(user, targetUserId, [...definition.required_scopes, "report:create", "report:*", "*"]);

    const reportId = randomUUID();
    const event = this.domainEvent("report.requested", user, "report", reportId, targetUserId, request, {
      report_id: reportId,
      report_type: body.report_type,
      format,
      requester_user_id: user.sub,
      target_user_id: targetUserId,
      date_from: body.date_from ?? null,
      date_to: body.date_to ?? null,
      filters: body.filters,
      options: body.options
    });

    const record = await this.db.transaction(async (client) => {
      const created = await this.repository.createReport(client, {
        reportId,
        tenant: user.tenant,
        requesterUserId: user.sub,
        targetUserId,
        reportType: body.report_type,
        format,
        filters: body.filters,
        options: body.options,
        dateFrom: body.date_from ?? null,
        dateTo: body.date_to ?? null,
        requestId: request.requestContext.requestId,
        traceId: request.requestContext.traceId,
        correlationId: request.requestContext.correlationId
      });
      await this.repository.insertGenerationJob(client, {
        jobId: reportId,
        reportId,
        tenant: user.tenant,
        queueName: this.config.report.bullmqQueueName,
        status: "QUEUED"
      });
      await this.repository.insertProgress(client, { reportId, tenant: user.tenant, stage: "queued", percent: 0, message: "Report queued" });
      await insertOutboxEvent(client, this.config.kafka.eventsTopic, event);
      return created;
    });

    await this.queue.addReportJob({
      report_id: reportId,
      request_id: request.requestContext.requestId,
      trace_id: request.requestContext.traceId,
      correlation_id: request.requestContext.correlationId
    });
    await this.invalidateReportCaches(reportId);
    void this.audit.writeAudit(event, { clientIp: request.ip, userAgent: requestUserAgent(request) });
    return publicReport(record);
  }

  public async listReports(user: AuthenticatedUser, query: ListReportsQuery): Promise<Record<string, unknown>> {
    if (query.target_user_id && query.target_user_id !== user.sub) {
      await this.assertTargetAccess(user, query.target_user_id, ["report:read", "report:*", "*"]);
    }
    const rows = await this.repository.list({
      tenant: user.tenant,
      requesterUserId: user.sub,
      targetUserId: query.target_user_id,
      status: query.status,
      limit: query.limit,
      offset: query.offset
    });
    return { reports: rows.map(publicReport), limit: query.limit, offset: query.offset };
  }

  public async getReport(user: AuthenticatedUser, reportId: string): Promise<Record<string, unknown>> {
    const record = await this.getAuthorizedReport(user, reportId, ["report:read", "report:*", "*"]);
    return publicReport(record);
  }

  public async cancelReport(user: AuthenticatedUser, reportId: string, request: FastifyRequest): Promise<Record<string, unknown>> {
    const record = await this.getAuthorizedReport(user, reportId, ["report:cancel", "report:*", "*"]);
    if (!["QUEUED", "PROCESSING"].includes(record.status)) {
      throw Errors.conflict("Only queued or processing reports can be cancelled", { report_id: reportId, status: record.status });
    }
    await this.queue.removeReportJob(reportId);
    const event = this.lifecycleEvent("report.cancelled", record, user.sub, request, { status: "CANCELLED", reason: "cancelled_by_requester" });
    const updated = await this.db.transaction(async (client) => {
      const row = await this.repository.markStatus(client, reportId, user.tenant, "CANCELLED");
      await this.repository.updateJobStatus(client, { reportId, tenant: user.tenant, status: "CANCELLED", progressPercent: 100, progressStage: "cancelled" });
      await this.repository.insertProgress(client, { reportId, tenant: user.tenant, stage: "cancelled", percent: 100, message: "Report cancelled" });
      await insertOutboxEvent(client, this.config.kafka.eventsTopic, event);
      return row;
    });
    if (!updated) throw Errors.notFound("Report not found", { report_id: reportId });
    await this.invalidateReportCaches(reportId);
    void this.audit.writeAudit(event, { clientIp: request.ip, userAgent: requestUserAgent(request) });
    return publicReport(updated);
  }

  public async retryReport(user: AuthenticatedUser, reportId: string, request: FastifyRequest): Promise<Record<string, unknown>> {
    const record = await this.getAuthorizedReport(user, reportId, ["report:retry", "report:*", "*"]);
    if (record.status !== "FAILED") throw Errors.conflict("Only failed reports can be retried", { report_id: reportId, status: record.status });
    const event = this.lifecycleEvent("report.retry_requested", record, user.sub, request, { status: "QUEUED" });
    const updated = await this.db.transaction(async (client) => {
      const row = await this.repository.markStatus(client, reportId, user.tenant, "QUEUED");
      await this.repository.insertGenerationJob(client, { jobId: reportId, reportId, tenant: user.tenant, queueName: this.config.report.bullmqQueueName, status: "QUEUED" });
      await this.repository.insertProgress(client, { reportId, tenant: user.tenant, stage: "queued", percent: 0, message: "Report retry queued" });
      await insertOutboxEvent(client, this.config.kafka.eventsTopic, event);
      return row;
    });
    await this.queue.addReportJob({ report_id: reportId, request_id: request.requestContext.requestId, trace_id: request.requestContext.traceId, correlation_id: request.requestContext.correlationId });
    await this.invalidateReportCaches(reportId);
    if (!updated) throw Errors.notFound("Report not found", { report_id: reportId });
    void this.audit.writeAudit(event, { clientIp: request.ip, userAgent: requestUserAgent(request) });
    return publicReport(updated);
  }

  public async deleteReport(user: AuthenticatedUser, reportId: string, request: FastifyRequest): Promise<Record<string, unknown>> {
    const record = await this.getAuthorizedReport(user, reportId, ["report:delete", "report:*", "*"]);
    const event = this.lifecycleEvent("report.deleted", record, user.sub, request, { status: "DELETED" });
    const updated = await this.db.transaction(async (client) => {
      const row = await this.repository.markStatus(client, reportId, user.tenant, "DELETED");
      await insertOutboxEvent(client, this.config.kafka.eventsTopic, event);
      return row;
    });
    await this.invalidateReportCaches(reportId);
    if (!updated) throw Errors.notFound("Report not found", { report_id: reportId });
    void this.audit.writeAudit(event, { clientIp: request.ip, userAgent: requestUserAgent(request) });
    return { report_id: reportId, deleted: true };
  }

  public async metadata(user: AuthenticatedUser, reportId: string): Promise<Record<string, unknown>> {
    const report = await this.getAuthorizedReport(user, reportId, ["report:read", "report:*", "*"]);
    if (report.status !== "COMPLETED") throw Errors.conflict("Report is not completed", { report_id: reportId, status: report.status });

    const cacheKey = this.cache.key(["report", reportId, "metadata"]);
    const cached = await this.cache.getJson<Record<string, unknown>>(cacheKey);
    if (cached) return cached;

    const file = await this.repository.getFile(reportId, user.tenant);
    if (!file) throw Errors.notFound("Report file not found", { report_id: reportId });
    const metadata = { report: publicReport(report), file };
    await this.cache.setJson(cacheKey, metadata);
    return metadata;
  }

  public async getDownloadFile(user: AuthenticatedUser, reportId: string, request?: FastifyRequest): Promise<{ report: ReportRequestRecord; file: NonNullable<Awaited<ReturnType<ReportRepository["getFile"]>>> }> {
    const report = await this.getAuthorizedReport(user, reportId, ["report:download", "report:*", "*"]);
    if (report.status !== "COMPLETED") throw Errors.conflict("Report is not completed", { report_id: reportId, status: report.status });
    const file = await this.repository.getFile(reportId, user.tenant);
    if (!file) throw Errors.notFound("Report file not found", { report_id: reportId });
    await this.repository.incrementDownloadCount(reportId, user.tenant);
    if (request) {
      const event = this.lifecycleEvent("report.downloaded", report, user.sub, request, { file_id: file.file_id, s3_object_key: file.s3_object_key });
      await this.db.transaction(async (client) => insertOutboxEvent(client, this.config.kafka.eventsTopic, event));
    }
    return { report, file };
  }

  public async preview(user: AuthenticatedUser, reportId: string, request?: FastifyRequest): Promise<Record<string, unknown>> {
    const report = await this.getAuthorizedReport(user, reportId, ["report:preview", "report:*", "*"]);

    const cacheKey = this.cache.key(["report", reportId, "preview"]);
    const cached = await this.cache.getJson<Record<string, unknown>>(cacheKey);
    if (cached) return cached;

    const file = await this.repository.getFile(reportId, user.tenant);
    if (!file) throw Errors.notFound("Report file not found", { report_id: reportId });
    let preview: Record<string, unknown>;
    if (file.preview_supported) {
      const result = await this.s3.getObjectAsBuffer(file.s3_object_key, this.config.report.previewMaxBytes);
      preview = {
        content: result.buffer.toString("utf8"),
        content_type: result.contentType ?? file.content_type,
        truncated: file.file_size_bytes > this.config.report.previewMaxBytes
      };
    } else {
      preview = {
        content: JSON.stringify({ report: publicReport(report), file, message: "Binary report preview returns safe metadata only." }, null, 2),
        content_type: "application/json; charset=utf-8",
        truncated: false
      };
    }
    await this.cache.setJson(cacheKey, preview);
    if (request) {
      const event = this.lifecycleEvent("report.previewed", report, user.sub, request, { file_id: file.file_id });
      await this.db.transaction(async (client) => insertOutboxEvent(client, this.config.kafka.eventsTopic, event));
    }
    return preview;
  }

  public async progress(user: AuthenticatedUser, reportId: string): Promise<Record<string, unknown>> {
    await this.getAuthorizedReport(user, reportId, ["report:read", "report:*", "*"]);
    const progress = await this.repository.getProgress(reportId, user.tenant);
    if (!progress) throw Errors.notFound("Report progress not found", { report_id: reportId });
    return progress as unknown as Record<string, unknown>;
  }

  public async events(user: AuthenticatedUser, reportId: string): Promise<Record<string, unknown>> {
    await this.getAuthorizedReport(user, reportId, ["report:read", "report:*", "*"]);
    return { events: await this.repository.listProgressEvents(reportId, user.tenant) };
  }

  public async files(user: AuthenticatedUser, reportId: string): Promise<Record<string, unknown>> {
    await this.getAuthorizedReport(user, reportId, ["report:read", "report:*", "*"]);
    return { files: await this.repository.getFiles(reportId, user.tenant) };
  }

  public async queueSummary(user: AuthenticatedUser): Promise<Record<string, unknown>> {
    this.assertManagementAccess(user);
    return { queue: await this.queue.summary() };
  }

  public async listTemplates(user: AuthenticatedUser): Promise<Record<string, unknown>> {
    this.assertManagementAccess(user);
    return { templates: await this.repository.listTemplates(user.tenant) };
  }

  public async getTemplate(user: AuthenticatedUser, templateId: string): Promise<Record<string, unknown>> {
    this.assertManagementAccess(user);
    const template = await this.repository.getTemplate(user.tenant, templateId);
    if (!template) throw Errors.notFound("Template not found", { template_id: templateId });
    return template as unknown as Record<string, unknown>;
  }

  public async createTemplate(user: AuthenticatedUser, body: CreateTemplateRequest, request: FastifyRequest): Promise<Record<string, unknown>> {
    this.assertManagementAccess(user);
    const definition = getReportType(body.report_type);
    if (!definition) throw Errors.validation("Unsupported report type", { error_code: "REPORT_TYPE_UNSUPPORTED", report_type: body.report_type });
    if (!definition.allowed_formats.includes(body.format)) throw Errors.validation("Unsupported template format", { error_code: "REPORT_FORMAT_UNSUPPORTED", format: body.format });
    const templateId = `tmpl-${randomUUID()}`;
    const event = this.domainEvent("report.template.created", user, "report_template", templateId, user.sub, request, { template_id: templateId, report_type: body.report_type, format: body.format });
    const template = await this.db.transaction(async (client) => {
      const created = await this.repository.createTemplate(client, { templateId, tenant: user.tenant, reportType: body.report_type, name: body.name, description: body.description ?? null, format: body.format, templateContent: body.template_content, schema: body.schema, style: body.style, createdBy: user.sub });
      await insertOutboxEvent(client, this.config.kafka.eventsTopic, event);
      return created;
    });
    void this.audit.writeAudit(event, { clientIp: request.ip, userAgent: requestUserAgent(request) });
    return template as unknown as Record<string, unknown>;
  }

  public async updateTemplate(user: AuthenticatedUser, templateId: string, body: UpdateTemplateRequest, request: FastifyRequest): Promise<Record<string, unknown>> {
    this.assertManagementAccess(user);
    const event = this.domainEvent("report.template.updated", user, "report_template", templateId, user.sub, request, { template_id: templateId });
    const template = await this.db.transaction(async (client) => {
      const updated = await this.repository.updateTemplate(client, user.tenant, templateId, { reportType: body.report_type, name: body.name, description: body.description, format: body.format, templateContent: body.template_content, schema: body.schema, style: body.style });
      if (!updated) throw Errors.notFound("Template not found", { template_id: templateId });
      await insertOutboxEvent(client, this.config.kafka.eventsTopic, event);
      return updated;
    });
    void this.audit.writeAudit(event, { clientIp: request.ip, userAgent: requestUserAgent(request) });
    return template as unknown as Record<string, unknown>;
  }

  public async setTemplateStatus(user: AuthenticatedUser, templateId: string, status: "ACTIVE" | "INACTIVE", request: FastifyRequest): Promise<Record<string, unknown>> {
    this.assertManagementAccess(user);
    const eventType = status === "ACTIVE" ? "report.template.activated" : "report.template.deactivated";
    const event = this.domainEvent(eventType, user, "report_template", templateId, user.sub, request, { template_id: templateId, status });
    const template = await this.db.transaction(async (client) => {
      const updated = await this.repository.setTemplateStatus(client, user.tenant, templateId, status);
      if (!updated) throw Errors.notFound("Template not found", { template_id: templateId });
      await insertOutboxEvent(client, this.config.kafka.eventsTopic, event);
      return updated;
    });
    void this.audit.writeAudit(event, { clientIp: request.ip, userAgent: requestUserAgent(request) });
    return template as unknown as Record<string, unknown>;
  }

  public async listSchedules(user: AuthenticatedUser): Promise<Record<string, unknown>> {
    const includeAll = isPrivileged(user);
    return { schedules: await this.repository.listSchedules(user.tenant, user.sub, includeAll) };
  }

  public async getSchedule(user: AuthenticatedUser, scheduleId: string): Promise<Record<string, unknown>> {
    const schedule = await this.repository.getSchedule(user.tenant, scheduleId);
    if (!schedule) throw Errors.notFound("Schedule not found", { schedule_id: scheduleId });
    if (schedule.owner_user_id !== user.sub && !isPrivileged(user)) await this.assertTargetAccess(user, schedule.target_user_id, ["report:schedule:manage", "report:*", "*"]);
    return schedule as unknown as Record<string, unknown>;
  }

  public async createSchedule(user: AuthenticatedUser, body: CreateScheduleRequest, request: FastifyRequest): Promise<Record<string, unknown>> {
    const definition = getReportType(body.report_type);
    if (!definition) throw Errors.validation("Unsupported report type", { error_code: "REPORT_TYPE_UNSUPPORTED", report_type: body.report_type });
    const format = body.format ?? definition.default_format;
    const targetUserId = body.target_user_id ?? user.sub;
    await this.assertTargetAccess(user, targetUserId, ["report:schedule:manage", "report:*", "*"]);
    const scheduleId = `sched-${randomUUID()}`;
    const event = this.domainEvent("report.schedule.created", user, "report_schedule", scheduleId, targetUserId, request, { schedule_id: scheduleId, report_type: body.report_type, format });
    const schedule = await this.db.transaction(async (client) => {
      const created = await this.repository.createSchedule(client, { scheduleId, tenant: user.tenant, ownerUserId: user.sub, targetUserId, reportType: body.report_type, format, cronExpression: body.cron_expression, timezone: body.timezone, filters: body.filters, options: body.options });
      await insertOutboxEvent(client, this.config.kafka.eventsTopic, event);
      return created;
    });
    void this.audit.writeAudit(event, { clientIp: request.ip, userAgent: requestUserAgent(request) });
    return schedule as unknown as Record<string, unknown>;
  }

  public async updateSchedule(user: AuthenticatedUser, scheduleId: string, body: UpdateScheduleRequest, request: FastifyRequest): Promise<Record<string, unknown>> {
    const schedule = await this.repository.getSchedule(user.tenant, scheduleId);
    if (!schedule) throw Errors.notFound("Schedule not found", { schedule_id: scheduleId });
    if (schedule.owner_user_id !== user.sub && !isPrivileged(user)) await this.assertTargetAccess(user, schedule.target_user_id, ["report:schedule:manage", "report:*", "*"]);
    const event = this.domainEvent("report.schedule.updated", user, "report_schedule", scheduleId, body.target_user_id ?? schedule.target_user_id, request, { schedule_id: scheduleId });
    const updated = await this.db.transaction(async (client) => {
      const row = await this.repository.updateSchedule(client, user.tenant, scheduleId, { targetUserId: body.target_user_id, reportType: body.report_type, format: body.format, cronExpression: body.cron_expression, timezone: body.timezone, filters: body.filters, options: body.options });
      if (!row) throw Errors.notFound("Schedule not found", { schedule_id: scheduleId });
      await insertOutboxEvent(client, this.config.kafka.eventsTopic, event);
      return row;
    });
    void this.audit.writeAudit(event, { clientIp: request.ip, userAgent: requestUserAgent(request) });
    return updated as unknown as Record<string, unknown>;
  }

  public async setScheduleStatus(user: AuthenticatedUser, scheduleId: string, status: "ACTIVE" | "PAUSED" | "DELETED", request: FastifyRequest): Promise<Record<string, unknown>> {
    const schedule = await this.repository.getSchedule(user.tenant, scheduleId);
    if (!schedule) throw Errors.notFound("Schedule not found", { schedule_id: scheduleId });
    if (schedule.owner_user_id !== user.sub && !isPrivileged(user)) await this.assertTargetAccess(user, schedule.target_user_id, ["report:schedule:manage", "report:*", "*"]);
    const eventType = status === "ACTIVE" ? "report.schedule.resumed" : status === "PAUSED" ? "report.schedule.paused" : "report.schedule.deleted";
    const event = this.domainEvent(eventType, user, "report_schedule", scheduleId, schedule.target_user_id, request, { schedule_id: scheduleId, status });
    const updated = await this.db.transaction(async (client) => {
      const row = await this.repository.setScheduleStatus(client, user.tenant, scheduleId, status);
      if (!row) throw Errors.notFound("Schedule not found", { schedule_id: scheduleId });
      await insertOutboxEvent(client, this.config.kafka.eventsTopic, event);
      return row;
    });
    void this.audit.writeAudit(event, { clientIp: request.ip, userAgent: requestUserAgent(request) });
    return updated as unknown as Record<string, unknown>;
  }

  public async listAudit(user: AuthenticatedUser, limit: number, offset: number): Promise<Record<string, unknown>> {
    this.assertManagementAccess(user);
    return { audit_events: await this.repository.listAudit(user.tenant, limit, offset), limit, offset };
  }

  public async getAudit(user: AuthenticatedUser, eventId: string): Promise<Record<string, unknown>> {
    this.assertManagementAccess(user);
    const audit = await this.repository.getAudit(user.tenant, eventId);
    if (!audit) throw Errors.notFound("Audit event not found", { event_id: eventId });
    return audit as unknown as Record<string, unknown>;
  }

  public async generateReport(reportId: string, jobContext: { request_id: string; trace_id: string; correlation_id: string }): Promise<void> {
    const start = Date.now();
    const report = await this.repository.getById(reportId, this.config.service.tenant);
    if (!report) throw new Error(`Report not found: ${reportId}`);
    if (!["QUEUED", "FAILED"].includes(report.status)) {
      this.logger.warn("report worker skipped non-queueable report", { event: "report.worker.skipped", user_id: report.target_user_id, extra: { report_id: reportId, status: report.status } });
      return;
    }

    const processingEvent = this.lifecycleEventFromContext("report.processing", report, report.requester_user_id, jobContext, { status: "PROCESSING" });
    await this.db.transaction(async (client) => {
      await this.repository.markStatus(client, reportId, report.tenant, "PROCESSING");
      await this.repository.updateJobStatus(client, { reportId, tenant: report.tenant, status: "PROCESSING", progressPercent: 10, progressStage: "loading_data" });
      await this.repository.insertProgress(client, { reportId, tenant: report.tenant, stage: "loading_data", percent: 10, message: "Loading local projections" });
      await insertOutboxEvent(client, this.config.kafka.eventsTopic, processingEvent);
    });

    try {
      const current = await this.repository.getById(reportId, report.tenant);
      if (!current) throw new Error(`Report vanished during generation: ${reportId}`);
      const datasets = await this.dataLoader.load(current as unknown as ReportRequestForGeneration);
      await this.updateProgress(current, "rendering", 45, "Rendering report", jobContext);
      const rendered = await renderReport(current as unknown as ReportRequestForGeneration, datasets);
      await this.updateProgress(current, "uploading", 75, "Uploading report to S3", jobContext);
      const key = reportFileKey(this.config, current.tenant, current.target_user_id, current.report_id, current.format);
      const fileName = safeFileName(`${current.report_type}_${current.report_id}.${rendered.extension}`);
      await this.s3.putObject({
        key,
        body: rendered.buffer,
        contentType: rendered.contentType,
        metadata: {
          report_id: current.report_id,
          report_type: current.report_type,
          tenant: current.tenant,
          target_user_id: current.target_user_id,
          requester_user_id: current.requester_user_id,
          format: current.format,
          content_type: rendered.contentType,
          checksum_sha256: rendered.checksumSha256,
          generated_at: new Date().toISOString(),
          trace_id: jobContext.trace_id,
          correlation_id: jobContext.correlation_id
        }
      });

      const completedEvent = this.lifecycleEventFromContext("report.completed", current, current.requester_user_id, jobContext, { status: "COMPLETED", s3_bucket: this.config.s3.bucket, s3_object_key: key, file_size_bytes: rendered.buffer.byteLength, checksum_sha256: rendered.checksumSha256 });
      await this.db.transaction(async (client) => {
        await this.repository.insertFile(client, {
          reportId,
          tenant: current.tenant,
          format: current.format,
          fileName,
          contentType: rendered.contentType,
          fileSizeBytes: rendered.buffer.byteLength,
          s3Bucket: this.config.s3.bucket,
          s3ObjectKey: key,
          checksumSha256: rendered.checksumSha256,
          previewSupported: rendered.previewSupported
        });
        await this.repository.markStatus(client, reportId, current.tenant, "COMPLETED");
        await this.repository.updateJobStatus(client, { reportId, tenant: current.tenant, status: "COMPLETED", durationMs: Date.now() - start, progressPercent: 100, progressStage: "completed" });
        await this.repository.insertProgress(client, { reportId, tenant: current.tenant, stage: "completed", percent: 100, message: "Report completed" });
        await insertOutboxEvent(client, this.config.kafka.eventsTopic, completedEvent);
      });
      await this.invalidateReportCaches(reportId);
      void this.audit.writeAudit(completedEvent);
      this.logger.info("report generation completed", { logger: "app.report", event: "report.generation.completed", user_id: current.target_user_id, actor_id: current.requester_user_id, request_id: jobContext.request_id, trace_id: jobContext.trace_id, correlation_id: jobContext.correlation_id, duration_ms: Date.now() - start, extra: { report_id: reportId, format: current.format } });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const failedEvent = this.lifecycleEventFromContext("report.failed", report, report.requester_user_id, jobContext, { status: "FAILED", error_code: "REPORT_GENERATION_FAILED", error_message: message });
      await this.db.transaction(async (client) => {
        await this.repository.markStatus(client, reportId, report.tenant, "FAILED", { errorCode: "REPORT_GENERATION_FAILED", errorMessage: message });
        await this.repository.updateJobStatus(client, { reportId, tenant: report.tenant, status: "FAILED", errorCode: "REPORT_GENERATION_FAILED", errorMessage: message, durationMs: Date.now() - start, progressPercent: 100, progressStage: "failed" });
        await this.repository.insertProgress(client, { reportId, tenant: report.tenant, stage: "failed", percent: 100, message, payload: { error_code: "REPORT_GENERATION_FAILED" } });
        await insertOutboxEvent(client, this.config.kafka.eventsTopic, failedEvent);
      });
      await this.invalidateReportCaches(reportId);
      void this.audit.writeAudit(failedEvent);
      throw error;
    }
  }

  private async updateProgress(record: ReportRequestRecord, stage: ReportProgressStage, percent: number, message: string, context: { request_id: string; trace_id: string; correlation_id: string }): Promise<void> {
    const event = this.lifecycleEventFromContext("report.progress_updated", record, record.requester_user_id, context, { progress_stage: stage, progress_percent: percent, message });
    await this.db.transaction(async (client) => {
      await this.repository.updateJobStatus(client, { reportId: record.report_id, tenant: record.tenant, status: "PROCESSING", progressPercent: percent, progressStage: stage });
      await this.repository.insertProgress(client, { reportId: record.report_id, tenant: record.tenant, stage, percent, message });
      await insertOutboxEvent(client, this.config.kafka.eventsTopic, event);
    });
    await this.cache.setJson(this.cache.key(["report", record.report_id, "progress"]), { report_id: record.report_id, stage, progress_percent: percent, message });
  }

  private async getAuthorizedReport(user: AuthenticatedUser, reportId: string, scopes: string[]): Promise<ReportRequestRecord> {
    const record = await this.repository.getById(reportId, user.tenant);
    if (!record) throw Errors.notFound("Report not found", { report_id: reportId });
    if (record.requester_user_id === user.sub || record.target_user_id === user.sub) return record;
    await this.assertTargetAccess(user, record.target_user_id, scopes);
    return record;
  }

  private async assertTargetAccess(user: AuthenticatedUser, targetUserId: string, scopes: string[]): Promise<void> {
    if (user.sub === targetUserId) return;
    if (isPrivileged(user)) return;
    const hasGrant = await this.repository.hasActiveGrant({ tenant: user.tenant, requesterUserId: user.sub, targetUserId, scopes });
    if (!hasGrant) throw Errors.forbidden("No approved access grant for target user", { target_user_id: targetUserId, error_code: "REPORT_ACCESS_DENIED" });
  }

  private assertManagementAccess(user: AuthenticatedUser): void {
    if (!isPrivileged(user)) throw Errors.forbidden("Approved admin, service, or system role required", { error_code: "REPORT_ACCESS_DENIED" });
  }

  private validateFilterKeys(filters: Record<string, unknown>, schema: Record<string, unknown>, reportType: string): void {
    const allowed = new Set(Object.keys(schema));
    const unknown = Object.keys(filters).filter((key) => !allowed.has(key));
    if (unknown.length > 0) throw Errors.validation("Unsupported report filter", { report_type: reportType, unsupported_filters: unknown });
  }

  private lifecycleEvent(eventType: string, record: ReportRequestRecord, actorId: string, request: FastifyRequest, payload: Record<string, unknown>): EventEnvelope {
    return createEventEnvelope(this.config, {
      eventType,
      tenant: record.tenant,
      userId: record.target_user_id,
      actorId,
      aggregateType: "report",
      aggregateId: record.report_id,
      requestId: request.requestContext.requestId,
      traceId: request.requestContext.traceId,
      correlationId: request.requestContext.correlationId,
      payload: { report_id: record.report_id, report_type: record.report_type, format: record.format, requester_user_id: record.requester_user_id, target_user_id: record.target_user_id, status: record.status, ...payload }
    });
  }

  private lifecycleEventFromContext(eventType: string, record: ReportRequestRecord, actorId: string, context: { request_id: string; trace_id: string; correlation_id: string }, payload: Record<string, unknown>): EventEnvelope {
    return createEventEnvelope(this.config, {
      eventType,
      tenant: record.tenant,
      userId: record.target_user_id,
      actorId,
      aggregateType: "report",
      aggregateId: record.report_id,
      requestId: context.request_id,
      traceId: context.trace_id,
      correlationId: context.correlation_id,
      payload: { report_id: record.report_id, report_type: record.report_type, format: record.format, requester_user_id: record.requester_user_id, target_user_id: record.target_user_id, status: record.status, ...payload }
    });
  }

  private domainEvent(eventType: string, user: AuthenticatedUser, aggregateType: string, aggregateId: string, targetUserId: string, request: FastifyRequest, payload: Record<string, unknown>): EventEnvelope {
    return createEventEnvelope(this.config, {
      eventType,
      tenant: user.tenant,
      userId: targetUserId,
      actorId: user.sub,
      aggregateType,
      aggregateId,
      requestId: request.requestContext.requestId,
      traceId: request.requestContext.traceId,
      correlationId: request.requestContext.correlationId,
      payload
    });
  }

  private async invalidateReportCaches(reportId: string): Promise<void> {
    await Promise.allSettled([
      this.cache.delete(this.cache.key(["report", reportId, "metadata"])),
      this.cache.delete(this.cache.key(["report", reportId, "preview"])),
      this.cache.delete(this.cache.key(["report", reportId, "progress"])),
      this.cache.delete(this.cache.key(["report", reportId]))
    ]);
  }
}
