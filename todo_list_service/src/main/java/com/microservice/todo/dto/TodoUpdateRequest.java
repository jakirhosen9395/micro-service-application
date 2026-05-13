package com.microservice.todo.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.microservice.todo.entity.TodoPriority;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;

public record TodoUpdateRequest(
        @Schema(example = "Updated todo title")
        @Size(max = 255, message = "title must be at most 255 characters")
        String title,

        @Size(max = 5000, message = "description must be at most 5000 characters")
        String description,

        TodoPriority priority,

        @JsonProperty("due_date") @JsonAlias("dueDate")
        Instant dueDate,

        List<String> tags
) {}
