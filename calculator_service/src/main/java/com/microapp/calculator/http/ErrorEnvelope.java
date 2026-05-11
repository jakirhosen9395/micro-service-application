package com.microapp.calculator.http;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.microapp.calculator.util.RequestContext;

import java.time.Instant;
import java.util.Map;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record ErrorEnvelope(
        String status,
        String message,
        String errorCode,
        Map<String, Object> details,
        String path,
        String requestId,
        String traceId,
        Instant timestamp
) {
    public static ErrorEnvelope of(String message, String errorCode, Map<String, Object> details, String path) {
        return new ErrorEnvelope(
                "error",
                message,
                errorCode,
                details == null ? Map.of() : details,
                path,
                RequestContext.requestId(),
                RequestContext.traceId(),
                Instant.now()
        );
    }
}
