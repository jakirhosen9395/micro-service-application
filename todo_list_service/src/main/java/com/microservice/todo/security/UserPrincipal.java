package com.microservice.todo.security;

import java.util.Collection;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;

public class UserPrincipal {
    private final String userId;
    private final String username;
    private final String email;
    private final String tenant;
    private final String role;
    private final String adminStatus;
    private final Map<String, Object> claims;

    public UserPrincipal(String userId, String username, String email, String tenant, String role, String adminStatus, Map<String, Object> claims) {
        this.userId = userId;
        this.username = username;
        this.email = email;
        this.tenant = tenant == null || tenant.isBlank() ? "dev" : tenant;
        this.role = role == null || role.isBlank() ? "user" : role.toLowerCase(Locale.ROOT);
        this.adminStatus = adminStatus == null || adminStatus.isBlank() ? "not_requested" : adminStatus.toLowerCase(Locale.ROOT);
        this.claims = Map.copyOf(claims);
    }

    public String getUserId() { return userId; }
    public String getUsername() { return username; }
    public String getEmail() { return email; }
    public String getTenant() { return tenant; }
    public String getRole() { return role; }
    public String getAdminStatus() { return adminStatus; }
    public Map<String, Object> getClaims() { return claims; }

    public boolean isService() { return "service".equals(role); }
    public boolean isSystem() { return "system".equals(role); }
    public boolean isServiceOrSystem() { return isService() || isSystem(); }
    public boolean isApprovedAdmin() { return "admin".equals(role) && "approved".equals(adminStatus); }

    public boolean canAccessUser(String targetUserId) {
        return userId.equals(targetUserId) || isServiceOrSystem() || isApprovedAdmin();
    }

    public Collection<? extends GrantedAuthority> authorities() {
        return List.of(new SimpleGrantedAuthority("ROLE_" + role.toUpperCase(Locale.ROOT)));
    }
}
