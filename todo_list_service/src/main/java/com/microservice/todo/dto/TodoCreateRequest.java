package com.microservice.todo.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.microservice.todo.entity.TodoPriority;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;

public record TodoCreateRequest(
        @Schema(example = "Verify todo_list_service requirements")
        @NotBlank(message = "title is required")
        @Size(max = 255, message = "title must be at most 255 characters")
        String title,

        @Schema(example = "Write and review the requirements document.")
        @Size(max = 5000, message = "description must be at most 5000 characters")
        String description,

        @Schema(example = "HIGH")
        TodoPriority priority,

        @Schema(example = "2026-05-10T18:00:00Z")
        @JsonProperty("due_date") @JsonAlias("dueDate")
        Instant dueDate,

        @Schema(example = "[\"work\",\"microservice\"]")
        List<String> tags
) {}
