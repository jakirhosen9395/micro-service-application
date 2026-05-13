package com.microapp.calculator.kafka;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.time.Instant;
import java.util.Map;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record EventEnvelope(
        String eventId,
        String eventType,
        String eventVersion,
        String service,
        String environment,
        String tenant,
        Instant timestamp,
        String requestId,
        String traceId,
        String correlationId,
        String userId,
        String actorId,
        String aggregateType,
        String aggregateId,
        Map<String, Object> payload
) {
}
