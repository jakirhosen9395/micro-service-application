package com.microservice.todo.security;

import jakarta.servlet.http.HttpServletRequest;

public final class PublicEndpoints {
    public static final String[] PATHS = {
            "/hello",
            "/health",
            "/docs"
    };

    private PublicEndpoints() {}

    public static boolean matches(HttpServletRequest request) {
        String path = request.getRequestURI();
        String contextPath = request.getContextPath();
        if (contextPath != null && !contextPath.isBlank() && path.startsWith(contextPath)) {
            path = path.substring(contextPath.length());
        }
        return path.equals("/hello") || path.equals("/health") || path.equals("/docs");
    }
}
