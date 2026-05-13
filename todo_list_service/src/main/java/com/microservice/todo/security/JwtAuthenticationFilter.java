package com.microservice.todo.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.microservice.todo.dto.ErrorResponse;
import com.microservice.todo.util.RequestContext;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.slf4j.MDC;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {
    private final JwtService jwtService;
    private final ObjectMapper objectMapper;

    public JwtAuthenticationFilter(JwtService jwtService, ObjectMapper objectMapper) {
        this.jwtService = jwtService;
        this.objectMapper = objectMapper;
    }


    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI();
        String contextPath = request.getContextPath();
        if (contextPath != null && !contextPath.isBlank() && path.startsWith(contextPath)) {
            path = path.substring(contextPath.length());
        }
        if (PublicEndpoints.matches(request)) {
            return true;
        }
        return !path.startsWith("/v1/") && !path.equals("/v1");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
            filterChain.doFilter(request, response);
            return;
        }

        String authHeader = request.getHeader(HttpHeaders.AUTHORIZATION);
        try {
            if (authHeader == null || !authHeader.startsWith("Bearer ")) {
                writeUnauthorized(response, request, "Authentication required", "UNAUTHORIZED");
                return;
            }

            String token = authHeader.substring(7).trim();
            var principal = jwtService.parseAndValidate(token);
            if (principal.isEmpty()) {
                writeUnauthorized(response, request, "Invalid or expired token", "UNAUTHORIZED");
                return;
            }

            var user = principal.get();
            var authentication = new UsernamePasswordAuthenticationToken(user, null, user.authorities());
            authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
            SecurityContextHolder.getContext().setAuthentication(authentication);
            RequestContext.set(user);
            MDC.put("userId", user.getUserId());
            MDC.put("tenant", user.getTenant());
            MDC.put("role", user.getRole());
            MDC.put("username", user.getUsername() == null ? "-" : user.getUsername());
            filterChain.doFilter(request, response);
        } catch (JwtService.TenantMismatchException ex) {
            writeForbidden(response, request, "Tenant mismatch", "TENANT_MISMATCH");
        } finally {
            MDC.remove("userId");
            MDC.remove("tenant");
            MDC.remove("role");
            MDC.remove("username");
            SecurityContextHolder.clearContext();
        }
    }

    private void writeForbidden(HttpServletResponse response, HttpServletRequest request, String message, String code) throws IOException {
        response.setStatus(HttpStatus.FORBIDDEN.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.getWriter().write(objectMapper.writerWithDefaultPrettyPrinter()
                .writeValueAsString(ErrorResponse.of(message, code, request.getRequestURI())));
    }

    private void writeUnauthorized(HttpServletResponse response, HttpServletRequest request, String message, String code) throws IOException {
        response.setStatus(HttpStatus.UNAUTHORIZED.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        objectMapper.writeValue(response.getOutputStream(), ErrorResponse.of(message, code, request.getRequestURI()));
    }
}
