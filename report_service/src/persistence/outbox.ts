import type { PoolClient } from "./postgres.js";
import type { AppConfig } from "../config/config.js";
import type { EventEnvelope } from "../events/envelope.js";
import type { KafkaBus } from "../kafka/kafka.js";
import type { AppLogger } from "../logging/logger.js";
import type { PostgresDatabase } from "./postgres.js";
import { withApmTransaction } from "../observability/apm.js";

export async function insertOutboxEvent(client: PoolClient, topic: string, envelope: EventEnvelope): Promise<void> {
  await client.query(
    `insert into report.outbox_events
      (event_id, tenant, aggregate_type, aggregate_id, event_type, event_version, topic, payload, request_id, trace_id, correlation_id)
     values ($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9,$10,$11)
     on conflict (event_id) do nothing`,
    [
      envelope.event_id,
      envelope.tenant,
      envelope.aggregate_type,
      envelope.aggregate_id,
      envelope.event_type,
      envelope.event_version,
      topic,
      JSON.stringify(envelope),
      envelope.request_id,
      envelope.trace_id,
      envelope.correlation_id
    ]
  );
}

interface OutboxRow {
  id: string;
  event_id: string;
  topic: string;
  payload: EventEnvelope;
  attempt_count: number;
}

export class OutboxPublisher {
  private timer?: NodeJS.Timeout;
  private stopped = false;

  public constructor(
    private readonly db: PostgresDatabase,
    private readonly kafka: KafkaBus,
    private readonly config: AppConfig,
    private readonly logger: AppLogger
  ) {}

  public start(intervalMs = 2000): void {
    this.stopped = false;
    this.timer = setInterval(() => {
      this.poll().catch((error: unknown) => {
        this.logger.error("outbox publisher poll failed", {
          logger: "app.kafka",
          event: "outbox.poll_failed",
          dependency: "kafka",
          exception_class: error instanceof Error ? error.name : "Error",
          exception_message: error instanceof Error ? error.message : String(error)
        });
      });
    }, intervalMs);
    this.timer.unref();
  }

  public async runForever(): Promise<never> {
    this.start();
    return new Promise<never>(() => undefined);
  }

  public async poll(limit = 25): Promise<void> {
    await withApmTransaction("outbox poll", "worker", { component: "outbox", limit }, async () => {
      const rows = await this.claimRows(limit);
      for (const row of rows) {
        await this.publishRow(row);
      }
    });
  }

  private async claimRows(limit: number): Promise<OutboxRow[]> {
    const result = await this.db.query<OutboxRow>(
      `with claimed as (
         select id from report.outbox_events
          where status in ('PENDING','FAILED')
            and (next_retry_at is null or next_retry_at <= now())
          order by created_at asc
          limit $1
          for update skip locked
       )
       update report.outbox_events o
          set status = 'PROCESSING', updated_at = now()
         from claimed
        where o.id = claimed.id
        returning o.id, o.event_id, o.topic, o.payload, o.attempt_count`,
      [limit]
    );
    return result.rows;
  }

  private async publishRow(row: OutboxRow): Promise<void> {
    try {
      await this.kafka.publish(row.topic, row.payload);
      await this.db.query(
        `update report.outbox_events set status='SENT', sent_at=now(), last_error=null, updated_at=now() where id=$1`,
        [row.id]
      );
      this.logger.debug("outbox event published", {
        logger: "app.kafka",
        event: "outbox.published",
        dependency: "kafka",
        trace_id: row.payload.trace_id,
        correlation_id: row.payload.correlation_id,
        extra: { event_id: row.event_id, event_type: row.payload.event_type, topic: row.topic }
      });
    } catch (error) {
      const nextAttempt = row.attempt_count + 1;
      const message = error instanceof Error ? error.message : String(error);
      if (nextAttempt >= 10) {
        await this.deadLetter(row, message, nextAttempt);
      } else {
        await this.db.query(
          `update report.outbox_events
              set status='FAILED', attempt_count=$2, last_error=$3,
                  next_retry_at=now() + interval '30 seconds', updated_at=now()
            where id=$1`,
          [row.id, nextAttempt, message]
        );
        this.logger.warn("outbox event publish failed and will retry", {
          logger: "app.kafka",
          event: "outbox.publish_retry_scheduled",
          dependency: "kafka",
          error_code: "KAFKA_PUBLISH_FAILED",
          trace_id: row.payload.trace_id,
          correlation_id: row.payload.correlation_id,
          extra: { event_id: row.event_id, attempt_count: nextAttempt }
        });
      }
    }
  }

  private async deadLetter(row: OutboxRow, reason: string, attemptCount: number): Promise<void> {
    try {
      await this.kafka.publish(this.config.kafka.deadLetterTopic, {
        ...row.payload,
        event_type: `${row.payload.event_type}.dead_lettered`,
        payload: { original: row.payload, reason, attempt_count: attemptCount }
      });
      await this.db.query(
        `update report.outbox_events
            set status='DEAD_LETTERED', attempt_count=$2, last_error=$3, updated_at=now()
          where id=$1`,
        [row.id, attemptCount, reason]
      );
    } catch (error) {
      await this.db.query(
        `update report.outbox_events
            set status='FAILED', attempt_count=$2, last_error=$3, next_retry_at=now() + interval '5 minutes', updated_at=now()
          where id=$1`,
        [row.id, attemptCount, error instanceof Error ? error.message : String(error)]
      );
    }
  }

  public stop(): void {
    this.stopped = true;
    if (this.timer) clearInterval(this.timer);
  }
}
