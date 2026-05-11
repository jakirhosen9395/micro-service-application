package com.microapp.calculator.http;

import com.microapp.calculator.logging.MongoStructuredLogger;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Map;

@Component
public class RequestLoggingFilter extends OncePerRequestFilter {
    private static final Logger log = LoggerFactory.getLogger(RequestLoggingFilter.class);
    private final MongoStructuredLogger mongoLogger;

    public RequestLoggingFilter(MongoStructuredLogger mongoLogger) {
        this.mongoLogger = mongoLogger;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain) throws ServletException, IOException {
        long start = System.nanoTime();
        Throwable failure = null;
        try {
            filterChain.doFilter(request, response);
        } catch (IOException | ServletException | RuntimeException ex) {
            failure = ex;
            throw ex;
        } finally {
            double durationMs = (System.nanoTime() - start) / 1_000_000.0;
            boolean suppress = failure == null && response.getStatus() < 400 && isSuppressedSystemPath(request.getMethod(), request.getRequestURI());
            if (!suppress) {
                String event = response.getStatus() >= 500 ? "http.request.failed" : "http.request.completed";
                String errorCode = response.getStatus() >= 400 ? "HTTP_" + response.getStatus() : null;
                log.info("event={} method={} path={} status_code={} duration_ms={}", event, request.getMethod(), request.getRequestURI(), response.getStatus(), Math.round(durationMs * 100.0) / 100.0);
                mongoLogger.request(event, "request completed", request.getMethod(), request.getRequestURI(), response.getStatus(), durationMs, errorCode, Map.of());
            }
        }
    }

    private boolean isSuppressedSystemPath(String method, String path) {
        return "GET".equalsIgnoreCase(method) && ("/hello".equals(path) || "/health".equals(path) || "/docs".equals(path));
    }
}
