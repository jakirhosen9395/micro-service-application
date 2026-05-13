package com.microservice.todo.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.List;

public record TodoHistoryData(@JsonProperty("todo_id") String todoId, List<TodoHistoryItem> items) {}
