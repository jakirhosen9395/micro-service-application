package com.microapp.calculator.exception;

import com.microapp.calculator.http.ErrorEnvelope;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.NoHandlerFoundException;

import java.util.LinkedHashMap;
import java.util.Map;

@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ErrorEnvelope> api(ApiException ex, HttpServletRequest request) {
        return ResponseEntity.status(ex.status()).body(ErrorEnvelope.of(ex.getMessage(), ex.errorCode(), ex.details(), request.getRequestURI()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorEnvelope> validation(MethodArgumentNotValidException ex, HttpServletRequest request) {
        Map<String, Object> details = new LinkedHashMap<>();
        ex.getBindingResult().getFieldErrors().forEach(err -> details.put(err.getField(), err.getDefaultMessage()));
        return ResponseEntity.badRequest().body(ErrorEnvelope.of("Validation failed", "VALIDATION_ERROR", details, request.getRequestURI()));
    }

    @ExceptionHandler(MissingServletRequestParameterException.class)
    public ResponseEntity<ErrorEnvelope> missingParameter(MissingServletRequestParameterException ex, HttpServletRequest request) {
        return ResponseEntity.badRequest().body(ErrorEnvelope.of("Missing required request parameter", "VALIDATION_ERROR", Map.of("parameter", ex.getParameterName()), request.getRequestURI()));
    }

    @ExceptionHandler(NoHandlerFoundException.class)
    public ResponseEntity<ErrorEnvelope> notFound(NoHandlerFoundException ex, HttpServletRequest request) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(ErrorEnvelope.of("Route not found", "NOT_FOUND", Map.of(), request.getRequestURI()));
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ErrorEnvelope> methodNotAllowed(HttpRequestMethodNotSupportedException ex, HttpServletRequest request) {
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED).body(ErrorEnvelope.of("Method not allowed", "METHOD_NOT_ALLOWED", Map.of(), request.getRequestURI()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorEnvelope> unhandled(Exception ex, HttpServletRequest request) {
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(ErrorEnvelope.of("Internal server error", "INTERNAL_ERROR", Map.of(), request.getRequestURI()));
    }
}
