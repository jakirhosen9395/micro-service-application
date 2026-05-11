package com.microapp.calculator.health;

import java.time.Instant;
import java.util.Map;

public record HealthResponse(
        String status,
        String service,
        String version,
        String environment,
        Instant timestamp,
        Map<String, DependencyResult> dependencies
) {
}
