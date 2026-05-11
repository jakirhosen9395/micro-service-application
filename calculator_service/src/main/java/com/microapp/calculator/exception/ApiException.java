package com.microapp.calculator.exception;

import org.springframework.http.HttpStatus;

import java.util.Map;

public class ApiException extends RuntimeException {
    private final HttpStatus status;
    private final String errorCode;
    private final Map<String, Object> details;

    public ApiException(HttpStatus status, String errorCode, String message) {
        this(status, errorCode, message, Map.of());
    }

    public ApiException(HttpStatus status, String errorCode, String message, Map<String, Object> details) {
        super(message);
        this.status = status;
        this.errorCode = errorCode;
        this.details = details == null ? Map.of() : details;
    }

    public HttpStatus status() { return status; }
    public String errorCode() { return errorCode; }
    public Map<String, Object> details() { return details; }
}
