package com.microservice.todo.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.microservice.todo.entity.TodoStatus;

public record StatusChangeData(
        String id,
        @JsonProperty("previous_status") TodoStatus previousStatus,
        @JsonProperty("current_status") TodoStatus currentStatus
) {}
