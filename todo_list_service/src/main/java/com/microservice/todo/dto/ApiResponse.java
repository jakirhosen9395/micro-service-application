package com.microservice.todo.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.time.Instant;
import org.slf4j.MDC;

public record ApiResponse<T>(
        String status,
        String message,
        T data,
        @JsonProperty("request_id") String requestId,
        @JsonProperty("trace_id") String traceId,
        Instant timestamp
) {
    public static <T> ApiResponse<T> ok(String message, T data) {
        return new ApiResponse<>("ok", message, data, valueOrDash(MDC.get("requestId")), valueOrDash(MDC.get("traceId")), Instant.now());
    }

    private static String valueOrDash(String value) {
        return value == null || value.isBlank() ? "-" : value;
    }
}
