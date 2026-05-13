package com.microservice.todo.dto;

public record HelloResponse(String status, String message, ServiceInfo service) {
    public record ServiceInfo(
            String name,
            String env,
            String version
    ) {}
}
