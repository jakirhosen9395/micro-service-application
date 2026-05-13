import type { EachMessagePayload } from "kafkajs";
import type { EventEnvelope } from "../events/envelope.js";
import type { KafkaBus } from "../kafka/kafka.js";
import type { AppLogger } from "../logging/logger.js";
import { redactSecrets } from "../logging/redaction.js";
import { insertInboxEvent, markInboxFailed, markInboxIgnored, markInboxProcessed } from "../persistence/inbox.js";
import type { PostgresDatabase } from "../persistence/postgres.js";
import { captureApmError, setApmLabels, setApmOutcome, setApmTransactionName } from "../observability/apm.js";

function payloadValue(envelope: EventEnvelope, key: string): unknown {
  return (envelope.payload as Record<string, unknown>)[key];
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function normalizeTimestamp(value: unknown): string | null {
  if (value === null || value === undefined || value === "") return null;

  if (typeof value === "number") return epochNumberToIso(value);

  if (typeof value === "string") {
    const trimmed = value.trim();
    if (!trimmed) return null;
    if (/^[+-]?\d+(?:\.\d+)?$/.test(trimmed)) return epochNumberToIso(Number(trimmed));

    const parsed = new Date(trimmed);
    return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
  }

  return null;
}

function epochNumberToIso(value: number): string | null {
  if (!Number.isFinite(value)) return null;

  const absolute = Math.abs(value);
  let milliseconds = value;
  if (absolute < 10_000_000_000) milliseconds = value * 1000;
  else if (absolute >= 10_000_000_000_000_000) milliseconds = value / 1_000_000;
  else if (absolute >= 10_000_000_000_000) milliseconds = value / 1000;

  const parsed = new Date(milliseconds);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function occurredAt(envelope: EventEnvelope): string | null {
  const value = payloadValue(envelope, "occurred_at") ?? payloadValue(envelope, "timestamp");
  return normalizeTimestamp(value) ?? normalizeTimestamp(envelope.timestamp);
}

function timestampField(envelope: EventEnvelope, key: string): string | null {
  return normalizeTimestamp(payloadValue(envelope, key));
}

function envelopeTimestamp(envelope: EventEnvelope): string | null {
  return normalizeTimestamp(envelope.timestamp);
}

function shouldApplyDomainProjection(eventType: string): boolean {
  return !eventType.includes(".audit.");
}

export class ProjectionService {
  public constructor(
    private readonly db: PostgresDatabase,
    private readonly kafka: KafkaBus,
    private readonly logger: AppLogger
  ) {}

  public async start(): Promise<void> {
    await this.kafka.runConsumer((payload) => this.handleMessage(payload));
  }

  public async handleMessage(messagePayload: EachMessagePayload): Promise<void> {
    const { topic, partition, message } = messagePayload;
    const envelope = this.kafka.parseMessage(message);
    setApmTransactionName(`Kafka ${envelope.event_type}`);
    setApmLabels({
      event_id: envelope.event_id,
      event_type: envelope.event_type,
      aggregate_type: envelope.aggregate_type,
      aggregate_id: envelope.aggregate_id,
      source_service: envelope.service,
      tenant: envelope.tenant,
      kafka_topic: topic,
      kafka_partition: partition,
      kafka_offset: message.offset
    });

    let projectionError: unknown;

    await this.db.transaction(async (client) => {
      const inserted = await insertInboxEvent(client, { envelope, topic, partition, offset: message.offset });
      if (!inserted) return;

      await client.query("savepoint kafka_inbox_projection");
      try {
        if (envelope.service === "report_service" && topic === "report.events") {
          await this.insertActivity(client, envelope);
          await markInboxIgnored(client, envelope.event_id);
        } else {
          await this.applyProjection(client, envelope);
          await this.insertActivity(client, envelope);
          await markInboxProcessed(client, envelope.event_id);
        }
        await client.query("release savepoint kafka_inbox_projection");
      } catch (error) {
        const messageText = error instanceof Error ? error.message : String(error);
        try {
          await client.query("rollback to savepoint kafka_inbox_projection");
          await markInboxFailed(client, envelope.event_id, messageText);
          await client.query("release savepoint kafka_inbox_projection");
          captureApmError(error, { event_id: envelope.event_id, event_type: envelope.event_type, dependency: "kafka" });
          setApmOutcome("failure");
          projectionError = error;
        } catch (markError) {
          captureApmError(markError, { event_id: envelope.event_id, event_type: envelope.event_type, dependency: "postgresql" });
          this.logger.error("Kafka inbox failed status update failed", {
            logger: "app.kafka",
            event: "kafka.inbox.mark_failed_failed",
            dependency: "postgresql",
            exception_class: markError instanceof Error ? markError.name : "Error",
            exception_message: markError instanceof Error ? markError.message : String(markError),
            stack_trace: markError instanceof Error ? markError.stack ?? null : null,
            extra: { topic, partition, offset: message.offset, event_id: envelope.event_id, event_type: envelope.event_type, original_error: messageText }
          });
          throw error;
        }
      }
    }).catch((error: unknown) => {
      this.logger.error("Kafka inbox projection failed", {
        logger: "app.kafka",
        event: "kafka.inbox.failed",
        dependency: "kafka",
        exception_class: error instanceof Error ? error.name : "Error",
        exception_message: error instanceof Error ? error.message : String(error),
        extra: { topic, partition, offset: message.offset, event_id: envelope.event_id, event_type: envelope.event_type }
      });
      throw error;
    });

    if (projectionError) {
      this.logger.error("Kafka inbox projection failed", {
        logger: "app.kafka",
        event: "kafka.inbox.failed",
        dependency: "kafka",
        exception_class: projectionError instanceof Error ? projectionError.name : "Error",
        exception_message: projectionError instanceof Error ? projectionError.message : String(projectionError),
        extra: { topic, partition, offset: message.offset, event_id: envelope.event_id, event_type: envelope.event_type }
      });
      throw projectionError;
    }
  }

  private async applyProjection(client: import("../persistence/postgres.js").PoolClient, envelope: EventEnvelope): Promise<void> {
    const type = envelope.aggregate_type.toLowerCase();
    const eventType = envelope.event_type.toLowerCase();
    if (!shouldApplyDomainProjection(eventType)) return;

    if (type.includes("user") || eventType.startsWith("auth.user") || eventType.startsWith("user.profile") || eventType.includes("user.")) {
      await this.upsertUser(client, envelope);
    }
    if (type.includes("calculation") || eventType.startsWith("calculation.")) {
      await this.upsertCalculation(client, envelope);
    }
    if (type.includes("todo") || eventType.startsWith("todo.")) {
      await this.upsertTodo(client, envelope);
    }
    if (type.includes("access") || eventType.startsWith("access.") || eventType.includes("access_grant")) {
      await this.upsertAccessGrant(client, envelope);
    }
    if (type.includes("admin") || eventType.startsWith("admin.") || eventType.includes("decision")) {
      await this.upsertAdminDecision(client, envelope);
    }
  }

  private async upsertUser(client: import("../persistence/postgres.js").PoolClient, envelope: EventEnvelope): Promise<void> {
    const userId = stringValue(payloadValue(envelope, "user_id")) ?? envelope.user_id;
    await client.query(
      `insert into report.report_user_projection (tenant, user_id, username, email, role, admin_status, status, payload)
       values ($1,$2,$3,$4,$5,$6,$7,$8::jsonb)
       on conflict (tenant, user_id) do update set
         username=coalesce(excluded.username, report.report_user_projection.username),
         email=coalesce(excluded.email, report.report_user_projection.email),
         role=coalesce(excluded.role, report.report_user_projection.role),
         admin_status=coalesce(excluded.admin_status, report.report_user_projection.admin_status),
         status=coalesce(excluded.status, report.report_user_projection.status),
         payload=excluded.payload,
         updated_at=now(),
         deleted_at=null`,
      [
        envelope.tenant,
        userId,
        stringValue(payloadValue(envelope, "username")),
        stringValue(payloadValue(envelope, "email")),
        stringValue(payloadValue(envelope, "role")),
        stringValue(payloadValue(envelope, "admin_status")),
        stringValue(payloadValue(envelope, "status")),
        JSON.stringify(redactSecrets(envelope.payload))
      ]
    );
  }

  private async upsertCalculation(client: import("../persistence/postgres.js").PoolClient, envelope: EventEnvelope): Promise<void> {
    const calculationId = stringValue(payloadValue(envelope, "calculation_id")) ?? envelope.aggregate_id;
    await client.query(
      `insert into report.report_calculation_projection (tenant, calculation_id, user_id, operation, status, payload, occurred_at)
       values ($1,$2,$3,$4,$5,$6::jsonb,$7)
       on conflict (tenant, calculation_id) do update set
         user_id=excluded.user_id,
         operation=coalesce(excluded.operation, report.report_calculation_projection.operation),
         status=coalesce(excluded.status, report.report_calculation_projection.status),
         payload=excluded.payload,
         occurred_at=coalesce(excluded.occurred_at, report.report_calculation_projection.occurred_at),
         updated_at=now(),
         deleted_at=null`,
      [
        envelope.tenant,
        calculationId,
        envelope.user_id,
        stringValue(payloadValue(envelope, "operation")),
        stringValue(payloadValue(envelope, "status")) ?? stringValue(payloadValue(envelope, "result_status")),
        JSON.stringify(redactSecrets(envelope.payload)),
        occurredAt(envelope)
      ]
    );
  }

  private async upsertTodo(client: import("../persistence/postgres.js").PoolClient, envelope: EventEnvelope): Promise<void> {
    const todoId = stringValue(payloadValue(envelope, "todo_id")) ?? envelope.aggregate_id;
    await client.query(
      `insert into report.report_todo_projection (tenant, todo_id, user_id, status, priority, payload, occurred_at)
       values ($1,$2,$3,$4,$5,$6::jsonb,$7)
       on conflict (tenant, todo_id) do update set
         user_id=excluded.user_id,
         status=coalesce(excluded.status, report.report_todo_projection.status),
         priority=coalesce(excluded.priority, report.report_todo_projection.priority),
         payload=excluded.payload,
         occurred_at=coalesce(excluded.occurred_at, report.report_todo_projection.occurred_at),
         updated_at=now(),
         deleted_at=null`,
      [
        envelope.tenant,
        todoId,
        envelope.user_id,
        stringValue(payloadValue(envelope, "status")),
        stringValue(payloadValue(envelope, "priority")),
        JSON.stringify(redactSecrets(envelope.payload)),
        occurredAt(envelope)
      ]
    );
  }

  private async upsertAccessGrant(client: import("../persistence/postgres.js").PoolClient, envelope: EventEnvelope): Promise<void> {
    const requester = stringValue(payloadValue(envelope, "requester_user_id")) ?? stringValue(payloadValue(envelope, "actor_id")) ?? envelope.actor_id;
    const target = stringValue(payloadValue(envelope, "target_user_id")) ?? envelope.user_id;
    const scope = stringValue(payloadValue(envelope, "scope")) ?? "*";
    await client.query(
      `insert into report.report_access_grant_projection
        (tenant, grant_id, requester_user_id, target_user_id, scope, status, granted_at, revoked_at, expires_at, payload)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::jsonb)
       on conflict (tenant, requester_user_id, target_user_id, scope) do update set
         grant_id=coalesce(excluded.grant_id, report.report_access_grant_projection.grant_id),
         status=excluded.status,
         granted_at=coalesce(excluded.granted_at, report.report_access_grant_projection.granted_at),
         revoked_at=excluded.revoked_at,
         expires_at=excluded.expires_at,
         payload=excluded.payload,
         updated_at=now(),
         deleted_at=null`,
      [
        envelope.tenant,
        stringValue(payloadValue(envelope, "grant_id")) ?? envelope.aggregate_id,
        requester,
        target,
        scope,
        stringValue(payloadValue(envelope, "status")) ?? (envelope.event_type.includes("revoked") ? "REVOKED" : "APPROVED"),
        timestampField(envelope, "granted_at") ?? (envelope.event_type.includes("approved") ? envelopeTimestamp(envelope) : null),
        timestampField(envelope, "revoked_at") ?? (envelope.event_type.includes("revoked") ? envelopeTimestamp(envelope) : null),
        timestampField(envelope, "expires_at"),
        JSON.stringify(redactSecrets(envelope.payload))
      ]
    );
  }

  private async upsertAdminDecision(client: import("../persistence/postgres.js").PoolClient, envelope: EventEnvelope): Promise<void> {
    const decisionId = stringValue(payloadValue(envelope, "decision_id")) ?? envelope.aggregate_id;
    await client.query(
      `insert into report.report_admin_decision_projection (tenant, decision_id, actor_id, target_user_id, decision, payload, occurred_at)
       values ($1,$2,$3,$4,$5,$6::jsonb,$7)
       on conflict (tenant, decision_id) do update set
         actor_id=excluded.actor_id,
         target_user_id=excluded.target_user_id,
         decision=excluded.decision,
         payload=excluded.payload,
         occurred_at=excluded.occurred_at,
         updated_at=now(),
         deleted_at=null`,
      [
        envelope.tenant,
        decisionId,
        envelope.actor_id,
        stringValue(payloadValue(envelope, "target_user_id")) ?? envelope.user_id,
        stringValue(payloadValue(envelope, "decision")) ?? envelope.event_type,
        JSON.stringify(redactSecrets(envelope.payload)),
        occurredAt(envelope)
      ]
    );
  }

  private async insertActivity(client: import("../persistence/postgres.js").PoolClient, envelope: EventEnvelope): Promise<void> {
    await client.query(
      `insert into report.report_activity_projection (tenant, activity_id, user_id, activity_type, source_service, payload, occurred_at)
       values ($1,$2,$3,$4,$5,$6::jsonb,$7)
       on conflict (tenant, activity_id) do nothing`,
      [
        envelope.tenant,
        envelope.event_id,
        envelope.user_id || envelope.actor_id,
        envelope.event_type,
        envelope.service,
        JSON.stringify(redactSecrets(envelope.payload)),
        envelopeTimestamp(envelope)
      ]
    );
  }
}
