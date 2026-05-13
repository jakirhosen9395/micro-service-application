import { randomUUID } from "node:crypto";
import type { AppConfig } from "../config/config.js";
import { redactSecrets } from "../logging/redaction.js";

export interface EventEnvelope<TPayload = Record<string, unknown>> {
  event_id: string;
  event_type: string;
  event_version: "1.0";
  service: "report_service";
  environment: string;
  tenant: string;
  timestamp: string;
  request_id: string;
  trace_id: string;
  correlation_id: string;
  user_id: string;
  actor_id: string;
  aggregate_type: string;
  aggregate_id: string;
  payload: TPayload;
}

export interface CreateEventInput<TPayload = Record<string, unknown>> {
  eventType: string;
  tenant: string;
  userId: string;
  actorId: string;
  aggregateType: string;
  aggregateId: string;
  requestId: string;
  traceId: string;
  correlationId: string;
  payload?: TPayload;
}

export function createEventEnvelope<TPayload extends Record<string, unknown>>(
  config: AppConfig,
  input: CreateEventInput<TPayload>
): EventEnvelope<TPayload> {
  return {
    event_id: `evt-${randomUUID()}`,
    event_type: input.eventType,
    event_version: "1.0",
    service: config.service.name,
    environment: config.service.environment,
    tenant: input.tenant,
    timestamp: new Date().toISOString(),
    request_id: input.requestId,
    trace_id: input.traceId,
    correlation_id: input.correlationId,
    user_id: input.userId,
    actor_id: input.actorId,
    aggregate_type: input.aggregateType,
    aggregate_id: input.aggregateId,
    payload: redactSecrets(input.payload ?? ({} as TPayload))
  };
}

export function kafkaMessageKey(envelope: EventEnvelope): string {
  return envelope.user_id ? `${envelope.tenant}:${envelope.user_id}` : `${envelope.tenant}:${envelope.aggregate_id}`;
}

export function eventHeaders(envelope: EventEnvelope): Record<string, string> {
  return {
    event_id: envelope.event_id,
    event_type: envelope.event_type,
    service: envelope.service,
    tenant: envelope.tenant,
    trace_id: envelope.trace_id,
    correlation_id: envelope.correlation_id
  };
}
