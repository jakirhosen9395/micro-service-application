package com.microservice.todo.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.time.Instant;
import java.util.Map;

public record TodoHistoryItem(
        String id,
        @JsonProperty("todo_id") String todoId,
        @JsonProperty("user_id") String userId,
        @JsonProperty("actor_id") String actorId,
        String tenant,
        @JsonProperty("event_type") String eventType,
        @JsonProperty("old_status") String oldStatus,
        @JsonProperty("new_status") String newStatus,
        Map<String, Object> changes,
        String reason,
        @JsonProperty("request_id") String requestId,
        @JsonProperty("trace_id") String traceId,
        @JsonProperty("client_ip") String clientIp,
        @JsonProperty("user_agent") String userAgent,
        @JsonProperty("created_at") Instant createdAt
) {}
