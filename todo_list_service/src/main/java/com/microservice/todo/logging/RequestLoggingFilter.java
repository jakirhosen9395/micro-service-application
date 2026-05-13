package com.microservice.todo.logging;

import com.microservice.todo.observability.ApmTraceContext;
import com.microservice.todo.util.RequestContext;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class RequestLoggingFilter extends OncePerRequestFilter {
    private static final Logger log = LoggerFactory.getLogger(RequestLoggingFilter.class);

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String requestId = firstNonBlank(request.getHeader("X-Request-ID"), request.getHeader("X-Request-Id"), UUID.randomUUID().toString());
        String correlationId = firstNonBlank(request.getHeader("X-Correlation-ID"), requestId);
        String traceId = firstNonBlank(extractTraceparent(request.getHeader("traceparent")), request.getHeader("X-Trace-ID"), requestId);
        String clientIp = clientIp(request);
        String userAgent = request.getHeader("User-Agent");
        long start = System.nanoTime();

        MDC.put("requestId", requestId);
        MDC.put("correlationId", correlationId);
        MDC.put("traceId", traceId);
        MDC.put("clientIp", clientIp);
        MDC.put("userAgent", userAgent == null ? "-" : userAgent);
        MDC.put("method", request.getMethod());
        MDC.put("path", request.getRequestURI());
        ApmTraceContext.putMdc();
        RequestContext.setMetadata(new RequestContext.RequestMetadata(requestId, correlationId, traceId, clientIp, userAgent));
        response.setHeader("X-Request-ID", requestId);
        response.setHeader("X-Correlation-ID", correlationId);
        response.setHeader("X-Trace-ID", traceId);

        try {
            filterChain.doFilter(request, response);
        } finally {
            long durationMs = (System.nanoTime() - start) / 1_000_000;
            ApmTraceContext.putMdc();
            MDC.put("statusCode", String.valueOf(response.getStatus()));
            MDC.put("durationMs", String.valueOf(durationMs));
            if (!isSuppressedSystemNoise(request.getRequestURI(), response.getStatus())) {
                log.info("event=http.request.completed message=request completed method={} path={} status_code={} duration_ms={} request_id={} trace_id={} user_id={}",
                        request.getMethod(), request.getRequestURI(), response.getStatus(), durationMs, requestId, traceId, MDC.get("userId"));
            }
            MDC.remove("requestId");
            MDC.remove("correlationId");
            MDC.remove("traceId");
            MDC.remove("clientIp");
            MDC.remove("userAgent");
            MDC.remove("method");
            MDC.remove("path");
            MDC.remove("statusCode");
            MDC.remove("durationMs");
            RequestContext.clear();
        }
    }

    private boolean isSuppressedSystemNoise(String path, int status) {
        return status < 400 && ("/health".equals(path) || "/hello".equals(path) || "/docs".equals(path));
    }

    private String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) return value.trim();
        }
        return UUID.randomUUID().toString();
    }

    private String extractTraceparent(String traceparent) {
        if (traceparent == null || traceparent.isBlank()) return null;
        String[] parts = traceparent.split("-");
        return parts.length >= 2 ? parts[1] : null;
    }

    private String clientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) return forwarded.split(",")[0].trim();
        String realIp = request.getHeader("X-Real-IP");
        if (realIp != null && !realIp.isBlank()) return realIp.trim();
        return request.getRemoteAddr();
    }
}
