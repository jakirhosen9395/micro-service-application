package com.microapp.calculator.util;

import com.microapp.calculator.security.UserPrincipal;

import java.time.Instant;
import java.util.UUID;

public final class RequestContext {
    private static final ThreadLocal<Context> CTX = new ThreadLocal<>();

    private RequestContext() {
    }

    public static Context init(String requestId, String traceId, String correlationId, String clientIp, String userAgent) {
        Context context = new Context(
                notBlank(requestId) ? requestId : "req-" + UUID.randomUUID(),
                notBlank(traceId) ? traceId : "trace-" + UUID.randomUUID(),
                notBlank(correlationId) ? correlationId : "corr-" + UUID.randomUUID(),
                clientIp,
                userAgent,
                null,
                Instant.now()
        );
        CTX.set(context);
        return context;
    }

    public static void attachUser(UserPrincipal user) {
        Context current = current();
        CTX.set(new Context(current.requestId(), current.traceId(), current.correlationId(), current.clientIp(), current.userAgent(), user, current.startedAt()));
    }

    public static Context current() {
        Context current = CTX.get();
        if (current != null) {
            return current;
        }
        return init(null, null, null, null, null);
    }

    public static UserPrincipal user() {
        UserPrincipal user = current().user();
        if (user == null) {
            throw new IllegalStateException("No authenticated user in request context");
        }
        return user;
    }

    public static String requestId() { return current().requestId(); }
    public static String traceId() { return current().traceId(); }
    public static String correlationId() { return current().correlationId(); }
    public static String clientIp() { return current().clientIp(); }
    public static String userAgent() { return current().userAgent(); }

    public static void clear() {
        CTX.remove();
    }

    private static boolean notBlank(String value) {
        return value != null && !value.isBlank();
    }

    public record Context(String requestId, String traceId, String correlationId, String clientIp, String userAgent, UserPrincipal user, Instant startedAt) {
    }
}
