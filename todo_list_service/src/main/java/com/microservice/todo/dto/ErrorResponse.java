package com.microservice.todo.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.time.Instant;
import java.util.Map;
import org.slf4j.MDC;

public record ErrorResponse(
        String status,
        String message,
        @JsonProperty("error_code") String errorCode,
        Map<String, Object> details,
        String path,
        @JsonProperty("request_id") String requestId,
        @JsonProperty("trace_id") String traceId,
        Instant timestamp
) {
    public static ErrorResponse of(String message, String errorCode, String path) {
        return of(message, errorCode, Map.of(), path);
    }

    public static ErrorResponse of(String message, String errorCode, Map<String, Object> details, String path) {
        return new ErrorResponse(
                "error",
                message,
                errorCode,
                details == null ? Map.of() : details,
                path,
                valueOrDash(MDC.get("requestId")),
                valueOrDash(MDC.get("traceId")),
                Instant.now());
    }

    private static String valueOrDash(String value) {
        return value == null || value.isBlank() ? "-" : value;
    }
}
