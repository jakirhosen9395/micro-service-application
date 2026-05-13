package com.microservice.todo.dto;

import com.microservice.todo.entity.TodoStatus;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotNull;

public record TodoStatusChangeRequest(
        @NotNull(message = "status is required")
        @Schema(example = "IN_PROGRESS")
        TodoStatus status,

        @Schema(example = "Started working on it")
        String reason
) {}
