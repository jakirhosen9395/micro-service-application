package com.microservice.todo.controller;

import com.microservice.todo.config.TodoProperties;
import com.microservice.todo.dto.HealthResponse;
import com.microservice.todo.dto.HelloResponse;
import com.microservice.todo.health.HealthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Tag(name = "system")
public class SystemController {
    private final TodoProperties properties;
    private final HealthService healthService;

    public SystemController(TodoProperties properties, HealthService healthService) {
        this.properties = properties;
        this.healthService = healthService;
    }

    @GetMapping("/hello")
    @Operation(summary = "Application running check", description = "Returns only service identity. It never checks dependencies and never exposes secrets.")
    public HelloResponse hello() {
        return new HelloResponse(
                "ok",
                properties.getServiceName() + " is running",
                new HelloResponse.ServiceInfo(
                        properties.getServiceName(),
                        displayEnvironment(properties.getEnv()),
                        properties.getServiceVersion()));
    }

    @GetMapping("/health")
    @Operation(summary = "Dependency health check", description = "Checks JWT, Postgres, Redis, Kafka, S3, MongoDB, APM, and Elasticsearch using the canonical health shape.")
    public ResponseEntity<HealthResponse> health() {
        HealthResponse response = healthService.health();
        HttpStatus status = "down".equals(response.status()) ? HttpStatus.SERVICE_UNAVAILABLE : HttpStatus.OK;
        return ResponseEntity.status(status).body(response);
    }

    private String displayEnvironment(String env) {
        return switch (env == null ? "" : env.toLowerCase()) {
            case "dev", "development" -> "development";
            case "stage", "staging" -> "stage";
            case "prod", "production" -> "production";
            default -> env;
        };
    }
}
