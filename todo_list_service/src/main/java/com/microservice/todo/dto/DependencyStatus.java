package com.microservice.todo.dto;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;

@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonPropertyOrder({"status", "latency_ms", "error_code"})
public record DependencyStatus(
        String status,
        @JsonProperty("latency_ms") double latencyMs,
        @JsonProperty("error_code") String errorCode
) {
    public static DependencyStatus ok(double latencyMs) {
        return new DependencyStatus("ok", latencyMs, null);
    }

    public static DependencyStatus down(double latencyMs, String errorCode) {
        return new DependencyStatus("down", latencyMs, errorCode);
    }

    @JsonIgnore
    public boolean healthy() {
        return "ok".equals(status);
    }
}
