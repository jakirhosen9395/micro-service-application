import type { PoolClient } from "./postgres.js";
import type { EventEnvelope } from "../events/envelope.js";

export async function insertInboxEvent(
  client: PoolClient,
  input: {
    envelope: EventEnvelope;
    topic: string;
    partition: number;
    offset: string;
  }
): Promise<boolean> {
  const result = await client.query(
    `insert into report.kafka_inbox_events
       (event_id, tenant, topic, partition, offset_value, event_type, source_service, payload, status)
     values ($1,$2,$3,$4,$5,$6,$7,$8::jsonb,'RECEIVED')
     on conflict do nothing`,
    [
      input.envelope.event_id,
      input.envelope.tenant,
      input.topic,
      input.partition,
      Number(input.offset),
      input.envelope.event_type,
      input.envelope.service,
      JSON.stringify(input.envelope)
    ]
  );
  return (result.rowCount ?? 0) > 0;
}

export async function markInboxProcessed(client: PoolClient, eventId: string): Promise<void> {
  await client.query(
    `update report.kafka_inbox_events set status='PROCESSED', processed_at=now(), error_message=null where event_id=$1`,
    [eventId]
  );
}

export async function markInboxIgnored(client: PoolClient, eventId: string): Promise<void> {
  await client.query(
    `update report.kafka_inbox_events set status='IGNORED', processed_at=now(), error_message=null where event_id=$1`,
    [eventId]
  );
}

export async function markInboxFailed(client: PoolClient, eventId: string, errorMessage: string): Promise<void> {
  await client.query(
    `update report.kafka_inbox_events set status='FAILED', processed_at=now(), error_message=$2 where event_id=$1`,
    [eventId, errorMessage]
  );
}
