package com.microservice.todo.util;

import com.microservice.todo.exception.ApiException;
import com.microservice.todo.security.UserPrincipal;
import java.util.Optional;
import org.slf4j.MDC;

public final class RequestContext {
    private static final ThreadLocal<UserPrincipal> CURRENT_USER = new ThreadLocal<>();
    private static final ThreadLocal<RequestMetadata> CURRENT_METADATA = new ThreadLocal<>();

    private RequestContext() {}

    public static void set(UserPrincipal principal) { CURRENT_USER.set(principal); }
    public static Optional<UserPrincipal> currentUser() { return Optional.ofNullable(CURRENT_USER.get()); }

    public static UserPrincipal requiredUser() {
        return currentUser().orElseThrow(() -> ApiException.unauthorized("Authentication is required"));
    }

    public static String requiredUserId() {
        return requiredUser().getUserId();
    }

    public static void setMetadata(RequestMetadata metadata) { CURRENT_METADATA.set(metadata); }
    public static RequestMetadata metadata() {
        RequestMetadata metadata = CURRENT_METADATA.get();
        if (metadata != null) return metadata;
        return new RequestMetadata(MDC.get("requestId"), MDC.get("correlationId"), MDC.get("traceId"), MDC.get("clientIp"), null);
    }

    public static String tenantOrDefault(String defaultTenant) {
        return currentUser().map(UserPrincipal::getTenant).filter(v -> !v.isBlank()).orElse(defaultTenant);
    }

    public static void clear() {
        CURRENT_USER.remove();
        CURRENT_METADATA.remove();
    }

    public record RequestMetadata(String requestId, String correlationId, String traceId, String clientIp, String userAgent) {}
}
