package com.microapp.calculator.security;

import java.util.Locale;

public record UserPrincipal(
        String userId,
        String tokenId,
        String username,
        String email,
        String role,
        String adminStatus,
        String tenant
) {
    public boolean isApprovedAdmin() {
        return "admin".equalsIgnoreCase(role) && "approved".equalsIgnoreCase(adminStatus);
    }

    public boolean isService() {
        return "service".equalsIgnoreCase(role) || "system".equalsIgnoreCase(role);
    }

    public String normalizedRole() {
        return role == null ? "user" : role.toLowerCase(Locale.ROOT);
    }
}
