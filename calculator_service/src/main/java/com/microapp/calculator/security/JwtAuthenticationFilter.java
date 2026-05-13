package com.microapp.calculator.security;

import com.microapp.calculator.exception.ApiException;
import com.microapp.calculator.http.ErrorResponseWriter;
import com.microapp.calculator.logging.MongoStructuredLogger;
import com.microapp.calculator.util.RequestContext;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;
import java.util.Map;

@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {
    private final JwtService jwtService;
    private final MongoStructuredLogger mongoLogger;

    public JwtAuthenticationFilter(JwtService jwtService, MongoStructuredLogger mongoLogger) {
        this.jwtService = jwtService;
        this.mongoLogger = mongoLogger;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !request.getRequestURI().startsWith("/v1/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain) throws ServletException, IOException {
        try {
            String header = request.getHeader("Authorization");
            if (header == null || !header.startsWith("Bearer ")) {
                throw new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "Authentication required");
            }
            UserPrincipal principal = jwtService.validate(header.substring(7).trim());
            RequestContext.attachUser(principal);
            MDC.put("user_id", principal.userId());
            MDC.put("actor_id", principal.userId());
            UsernamePasswordAuthenticationToken authentication = new UsernamePasswordAuthenticationToken(
                    principal,
                    null,
                    List.of(new SimpleGrantedAuthority("ROLE_" + principal.normalizedRole().toUpperCase()))
            );
            SecurityContextHolder.getContext().setAuthentication(authentication);
            filterChain.doFilter(request, response);
        } catch (ApiException ex) {
            SecurityContextHolder.clearContext();
            mongoLogger.warn("authentication.failed", ex.getMessage(), ex.errorCode(), Map.of("path", request.getRequestURI()));
            ErrorResponseWriter.write(request, response, ex.status(), ex.getMessage(), ex.errorCode(), ex.details());
        }
    }
}
