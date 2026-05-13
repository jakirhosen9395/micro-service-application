package com.microapp.calculator.http;

import com.microapp.calculator.observability.ApmTraceContext;
import com.microapp.calculator.util.RequestContext;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

@Component("calculatorRequestContextFilter")
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestContextFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain) throws ServletException, IOException {
        RequestContext.Context context = RequestContext.init(
                header(request, "X-Request-ID"),
                header(request, "X-Trace-ID"),
                header(request, "X-Correlation-ID"),
                clientIp(request),
                request.getHeader("User-Agent")
        );
        MDC.put("request_id", context.requestId());
        MDC.put("trace_id", context.traceId());
        MDC.put("correlation_id", context.correlationId());
        ApmTraceContext.putMdc();
        response.setHeader("X-Request-ID", context.requestId());
        response.setHeader("X-Trace-ID", context.traceId());
        response.setHeader("X-Correlation-ID", context.correlationId());
        try {
            filterChain.doFilter(request, response);
        } finally {
            ApmTraceContext.putMdc();
            MDC.clear();
            RequestContext.clear();
        }
    }

    private static String header(HttpServletRequest request, String name) {
        String value = request.getHeader(name);
        return value == null || value.isBlank() ? null : value.trim();
    }

    private static String clientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }
}
