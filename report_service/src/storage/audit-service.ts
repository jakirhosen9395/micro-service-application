import type { AppConfig } from "../config/config.js";
import type { EventEnvelope } from "../events/envelope.js";
import { createEventEnvelope } from "../events/envelope.js";
import type { AppLogger } from "../logging/logger.js";
import { redactSecrets } from "../logging/redaction.js";
import type { PostgresDatabase } from "../persistence/postgres.js";
import { insertOutboxEvent } from "../persistence/outbox.js";
import { auditEventKey } from "./paths.js";
import type { S3Storage } from "./s3.js";

export interface AuditContext {
  clientIp?: string;
  userAgent?: string;
}

export class AuditService {
  public constructor(
    private readonly config: AppConfig,
    private readonly db: PostgresDatabase,
    private readonly s3: S3Storage,
    private readonly logger: AppLogger
  ) {}

  public async writeAudit(envelope: EventEnvelope, context: AuditContext = {}): Promise<void> {
    const objectKey = auditEventKey(this.config, envelope.tenant, envelope.actor_id, envelope.event_type, envelope.event_id, new Date(envelope.timestamp));
    const objectBody = redactSecrets({
      event_id: envelope.event_id,
      event_type: envelope.event_type,
      service: envelope.service,
      environment: envelope.environment,
      tenant: envelope.tenant,
      user_id: envelope.user_id,
      actor_id: envelope.actor_id,
      target_user_id: envelope.payload?.target_user_id ?? null,
      aggregate_type: envelope.aggregate_type,
      aggregate_id: envelope.aggregate_id,
      request_id: envelope.request_id,
      trace_id: envelope.trace_id,
      correlation_id: envelope.correlation_id,
      client_ip: context.clientIp ?? null,
      user_agent: context.userAgent ?? null,
      timestamp: envelope.timestamp,
      payload: envelope.payload
    });

    try {
      await this.s3.putObject({ key: objectKey, body: JSON.stringify(objectBody, null, 2), contentType: "application/json" });
      const auditEnvelope = createEventEnvelope(this.config, {
        eventType: "report.audit.s3_written",
        tenant: envelope.tenant,
        userId: envelope.user_id,
        actorId: envelope.actor_id,
        aggregateType: "report_audit",
        aggregateId: envelope.event_id,
        requestId: envelope.request_id,
        traceId: envelope.trace_id,
        correlationId: envelope.correlation_id,
        payload: { report_event_id: envelope.event_id, report_event_type: envelope.event_type, s3_bucket: this.config.s3.bucket, s3_object_key: objectKey }
      });
      await this.db.transaction(async (client) => {
        await client.query(
          `insert into report.report_audit_events
             (tenant, report_id, event_id, event_type, actor_id, target_user_id, s3_bucket, s3_object_key, payload)
           values ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb)
           on conflict (tenant, event_id) do nothing`,
          [
            envelope.tenant,
            envelope.aggregate_type === "report" ? envelope.aggregate_id : null,
            envelope.event_id,
            envelope.event_type,
            envelope.actor_id,
            envelope.payload?.target_user_id ?? null,
            this.config.s3.bucket,
            objectKey,
            JSON.stringify(objectBody)
          ]
        );
        await insertOutboxEvent(client, this.config.kafka.eventsTopic, auditEnvelope);
      });
    } catch (error) {
      this.logger.error("S3 audit snapshot write failed", {
        logger: "app.s3",
        event: "s3.audit_write_failed",
        dependency: "s3",
        request_id: envelope.request_id,
        trace_id: envelope.trace_id,
        correlation_id: envelope.correlation_id,
        user_id: envelope.user_id,
        actor_id: envelope.actor_id,
        error_code: "S3_AUDIT_WRITE_FAILED",
        exception_class: error instanceof Error ? error.name : "Error",
        exception_message: error instanceof Error ? error.message : String(error),
        extra: { event_id: envelope.event_id, object_key: objectKey }
      });
    }
  }
}
