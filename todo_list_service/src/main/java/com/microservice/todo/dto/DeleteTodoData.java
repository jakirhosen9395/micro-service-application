package com.microservice.todo.dto;

import java.time.Instant;

public record DeleteTodoData(String id, boolean deleted, boolean hardDeleted, Instant deletedAt) {}
