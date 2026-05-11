package com.microapp.calculator.domain;

import com.microapp.calculator.exception.ApiException;
import com.microapp.calculator.persistence.AccessGrantRepository;
import com.microapp.calculator.security.UserPrincipal;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

@Service
public class PermissionService {
    private static final String CALCULATOR_HISTORY_READ = "calculator:history:read";
    private final AccessGrantRepository accessGrantRepository;

    public PermissionService(AccessGrantRepository accessGrantRepository) {
        this.accessGrantRepository = accessGrantRepository;
    }

    public void requireCanReadUser(UserPrincipal actor, String targetUserId) {
        if (actor.userId().equals(targetUserId) || actor.isApprovedAdmin() || actor.isService()) {
            return;
        }
        if (accessGrantRepository.hasActiveGrant(actor.tenant(), targetUserId, actor.userId(), CALCULATOR_HISTORY_READ)) {
            return;
        }
        throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Caller is not allowed to read this user's calculator history");
    }
}
