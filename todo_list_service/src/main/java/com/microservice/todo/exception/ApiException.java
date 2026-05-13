package com.microservice.todo.exception;

import org.springframework.http.HttpStatus;

public class ApiException extends RuntimeException {
    private final HttpStatus status;
    private final String errorCode;

    public ApiException(HttpStatus status, String errorCode, String message) {
        super(message);
        this.status = status;
        this.errorCode = errorCode;
    }

    public HttpStatus getStatus() { return status; }
    public String getErrorCode() { return errorCode; }

    public static ApiException notFound(String message) { return new ApiException(HttpStatus.NOT_FOUND, "TODO_NOT_FOUND", message); }
    public static ApiException badRequest(String message) { return new ApiException(HttpStatus.BAD_REQUEST, "TODO_VALIDATION_ERROR", message); }
    public static ApiException invalidTransition(String message) { return new ApiException(HttpStatus.CONFLICT, "TODO_INVALID_STATUS_TRANSITION", message); }
    public static ApiException unauthorized(String message) { return new ApiException(HttpStatus.UNAUTHORIZED, "TODO_UNAUTHORIZED", message); }
    public static ApiException forbidden(String message) { return new ApiException(HttpStatus.FORBIDDEN, "TODO_FORBIDDEN", message); }
}
