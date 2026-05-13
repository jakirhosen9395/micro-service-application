package com.microservice.todo.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.time.Instant;

public record TodoEvent(
        @JsonProperty("event_id") String eventId,
        @JsonProperty("event_type") String eventType,
        @JsonProperty("event_version") String eventVersion,
        String service,
        String environment,
        String tenant,
        Instant timestamp,
        @JsonProperty("request_id") String requestId,
        @JsonProperty("trace_id") String traceId,
        @JsonProperty("correlation_id") String correlationId,
        @JsonProperty("user_id") String userId,
        @JsonProperty("actor_id") String actorId,
        @JsonProperty("aggregate_type") String aggregateType,
        @JsonProperty("aggregate_id") String aggregateId,
        Object payload
) {
    public String todoId() {
        return aggregateId == null || aggregateId.isBlank() ? eventId : aggregateId;
    }
}
