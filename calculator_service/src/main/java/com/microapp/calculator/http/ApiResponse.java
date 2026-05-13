package com.microapp.calculator.http;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.microapp.calculator.util.RequestContext;

import java.time.Instant;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record ApiResponse<T>(
        String status,
        String message,
        T data,
        String requestId,
        String traceId,
        Instant timestamp
) {
    public static <T> ApiResponse<T> ok(String message, T data) {
        return new ApiResponse<>("ok", message, data, RequestContext.requestId(), RequestContext.traceId(), Instant.now());
    }
}
