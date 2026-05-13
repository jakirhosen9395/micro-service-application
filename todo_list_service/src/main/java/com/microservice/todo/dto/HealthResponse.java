package com.microservice.todo.dto;

import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import java.time.Instant;
import java.util.Map;

@JsonPropertyOrder({"status", "service", "version", "environment", "timestamp", "dependencies"})
public record HealthResponse(
        String status,
        String service,
        String version,
        String environment,
        Instant timestamp,
        Map<String, DependencyStatus> dependencies
) {}
