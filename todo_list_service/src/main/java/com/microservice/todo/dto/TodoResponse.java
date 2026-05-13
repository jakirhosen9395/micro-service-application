package com.microservice.todo.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.microservice.todo.entity.TodoPriority;
import com.microservice.todo.entity.TodoStatus;
import java.time.Instant;
import java.util.List;

public record TodoResponse(
        String id,
        @JsonProperty("user_id") String userId,
        String username,
        String email,
        String tenant,
        String title,
        String description,
        TodoStatus status,
        TodoPriority priority,
        @JsonProperty("due_date") Instant dueDate,
        List<String> tags,
        boolean archived,
        @JsonProperty("completed_at") Instant completedAt,
        @JsonProperty("archived_at") Instant archivedAt,
        @JsonProperty("deleted_at") Instant deletedAt,
        @JsonProperty("created_at") Instant createdAt,
        @JsonProperty("updated_at") Instant updatedAt,
        @JsonProperty("request_id") String requestId,
        @JsonProperty("trace_id") String traceId,
        @JsonProperty("s3_object_key") String s3ObjectKey
) {}
