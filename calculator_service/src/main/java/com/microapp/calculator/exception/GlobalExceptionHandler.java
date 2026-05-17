package com.microapp.calculator.exception;

import com.microapp.calculator.http.ErrorEnvelope;
import co.elastic.apm.api.ElasticApm;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.HttpMediaTypeNotAcceptableException;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.NoHandlerFoundException;

import java.util.LinkedHashMap;
import java.util.Map;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ErrorEnvelope> api(ApiException ex, HttpServletRequest request) {
        return ResponseEntity.status(ex.status())
                .body(ErrorEnvelope.of(ex.getMessage(), ex.errorCode(), ex.details(), request.getRequestURI()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorEnvelope> validation(MethodArgumentNotValidException ex, HttpServletRequest request) {
        Map<String, Object> details = new LinkedHashMap<>();
        ex.getBindingResult().getFieldErrors().forEach(err -> details.put(err.getField(), err.getDefaultMessage()));

        return ResponseEntity.badRequest()
                .body(ErrorEnvelope.of("Validation failed", "VALIDATION_ERROR", details, request.getRequestURI()));
    }

    @ExceptionHandler(MissingServletRequestParameterException.class)
    public ResponseEntity<ErrorEnvelope> missingParameter(
            MissingServletRequestParameterException ex,
            HttpServletRequest request
    ) {
        return ResponseEntity.badRequest()
                .body(ErrorEnvelope.of(
                        "Missing required request parameter",
                        "VALIDATION_ERROR",
                        Map.of("parameter", ex.getParameterName()),
                        request.getRequestURI()
                ));
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ErrorEnvelope> messageNotReadable(
            HttpMessageNotReadableException ex,
            HttpServletRequest request
    ) {
        Map<String, Object> details = new LinkedHashMap<>();
        details.put("reason", "Malformed JSON request body or incompatible field type");

        Throwable root = rootCause(ex);
        if (root != null && root.getMessage() != null && !root.getMessage().isBlank()) {
            details.put("cause", sanitize(root.getMessage()));
        }

        return ResponseEntity.badRequest()
                .body(ErrorEnvelope.of(
                        "Malformed JSON request body or incompatible field type",
                        "VALIDATION_ERROR",
                        details,
                        request.getRequestURI()
                ));
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<ErrorEnvelope> typeMismatch(
            MethodArgumentTypeMismatchException ex,
            HttpServletRequest request
    ) {
        Map<String, Object> details = new LinkedHashMap<>();
        details.put("parameter", ex.getName());
        details.put("value", ex.getValue() == null ? null : String.valueOf(ex.getValue()));

        Class<?> requiredType = ex.getRequiredType();
        if (requiredType != null) {
            details.put("expected_type", requiredType.getSimpleName());
        }

        return ResponseEntity.badRequest()
                .body(ErrorEnvelope.of(
                        "Invalid request parameter type",
                        "VALIDATION_ERROR",
                        details,
                        request.getRequestURI()
                ));
    }

    @ExceptionHandler(HttpMediaTypeNotAcceptableException.class)
    public ResponseEntity<ErrorEnvelope> notAcceptable(
            HttpMediaTypeNotAcceptableException ex,
            HttpServletRequest request
    ) {
        Map<String, Object> details = new LinkedHashMap<>();
        details.put("accept", request.getHeader("Accept"));
        details.put("supported_media_types", ex.getSupportedMediaTypes().stream().map(Object::toString).toList());

        return ResponseEntity.status(HttpStatus.NOT_ACCEPTABLE)
                .body(ErrorEnvelope.of(
                        "Requested media type is not acceptable",
                        "NOT_ACCEPTABLE",
                        details,
                        request.getRequestURI()
                ));
    }

    @ExceptionHandler(HttpMediaTypeNotSupportedException.class)
    public ResponseEntity<ErrorEnvelope> unsupportedMediaType(
            HttpMediaTypeNotSupportedException ex,
            HttpServletRequest request
    ) {
        Map<String, Object> details = new LinkedHashMap<>();
        details.put("content_type", ex.getContentType() == null ? null : ex.getContentType().toString());
        details.put("supported_media_types", ex.getSupportedMediaTypes().stream().map(Object::toString).toList());

        return ResponseEntity.status(HttpStatus.UNSUPPORTED_MEDIA_TYPE)
                .body(ErrorEnvelope.of(
                        "Unsupported media type",
                        "UNSUPPORTED_MEDIA_TYPE",
                        details,
                        request.getRequestURI()
                ));
    }

    @ExceptionHandler(NoHandlerFoundException.class)
    public ResponseEntity<ErrorEnvelope> notFound(NoHandlerFoundException ex, HttpServletRequest request) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(ErrorEnvelope.of("Route not found", "NOT_FOUND", Map.of(), request.getRequestURI()));
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ErrorEnvelope> methodNotAllowed(
            HttpRequestMethodNotSupportedException ex,
            HttpServletRequest request
    ) {
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED)
                .body(ErrorEnvelope.of("Method not allowed", "METHOD_NOT_ALLOWED", Map.of(), request.getRequestURI()));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ErrorEnvelope> illegalArgument(IllegalArgumentException ex, HttpServletRequest request) {
        return ResponseEntity.badRequest()
                .body(ErrorEnvelope.of(
                        "Invalid request value",
                        "VALIDATION_ERROR",
                        Map.of("reason", sanitize(ex.getMessage() == null ? "Invalid value" : ex.getMessage())),
                        request.getRequestURI()
                ));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorEnvelope> unhandled(Exception ex, HttpServletRequest request) {
        ElasticApm.currentTransaction().captureException(ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ErrorEnvelope.of("Internal server error", "INTERNAL_ERROR", Map.of(), request.getRequestURI()));
    }

    private static Throwable rootCause(Throwable throwable) {
        Throwable current = throwable;
        while (current != null && current.getCause() != null && current.getCause() != current) {
            current = current.getCause();
        }
        return current;
    }

    private static String sanitize(String message) {
        return message.length() <= 500 ? message : message.substring(0, 500);
    }
}
