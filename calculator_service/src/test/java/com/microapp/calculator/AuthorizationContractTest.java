package com.microapp.calculator;

import com.microapp.calculator.domain.PermissionService;
import com.microapp.calculator.exception.ApiException;
import com.microapp.calculator.persistence.AccessGrantRepository;
import com.microapp.calculator.security.UserPrincipal;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class AuthorizationContractTest {
    @Test
    void sameUserApprovedAdminServiceAndSystemCanReadHistory() {
        AccessGrantRepository grants = mock(AccessGrantRepository.class);
        PermissionService service = new PermissionService(grants);
        service.requireCanReadUser(new UserPrincipal("u1", "jti", "u", "u@example.com", "user", "not_requested", "dev"), "u1");
        service.requireCanReadUser(new UserPrincipal("admin", "jti", "a", "a@example.com", "admin", "approved", "dev"), "u1");
        service.requireCanReadUser(new UserPrincipal("svc", "jti", "s", "s@example.com", "service", "not_requested", "dev"), "u1");
        service.requireCanReadUser(new UserPrincipal("sys", "jti", "s", "s@example.com", "system", "not_requested", "dev"), "u1");
    }

    @Test
    void activeProjectedGrantAllowsCrossUserReadAndMissingGrantDenies() {
        AccessGrantRepository grants = mock(AccessGrantRepository.class);
        when(grants.hasActiveGrant("dev", "target", "reader", "calculator:history:read")).thenReturn(true);
        PermissionService service = new PermissionService(grants);
        service.requireCanReadUser(new UserPrincipal("reader", "jti", "r", "r@example.com", "user", "not_requested", "dev"), "target");
        assertThrows(ApiException.class, () -> service.requireCanReadUser(new UserPrincipal("blocked", "jti", "b", "b@example.com", "user", "not_requested", "dev"), "target"));
    }
}
