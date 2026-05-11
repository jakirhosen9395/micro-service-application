package com.microapp.calculator;

import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertTrue;

class SecurityContractTest {
    @Test
    void jwtServiceRequiresCanonicalClaimsAlgorithmAudienceAndTenant() throws Exception {
        String source = Files.readString(Path.of("src/main/java/com/microapp/calculator/security/JwtService.java"));
        for (String claim : new String[]{"sub", "jti", "username", "email", "role", "admin_status", "tenant"}) {
            assertTrue(source.contains("requiredString(claims, \"" + claim + "\")"), "missing claim " + claim);
        }
        assertTrue(source.contains("requireTemporalClaims(claims)"));
        assertTrue(source.contains("getIssuedAt()"));
        assertTrue(source.contains("getNotBefore()"));
        assertTrue(source.contains("getExpiration()"));
        assertTrue(source.contains("\"HS256\".equals(parsed.getHeader().getAlgorithm())"));
        assertTrue(source.contains("requireAudience(claims)"));
        assertTrue(source.contains("TENANT_MISMATCH"));
        assertTrue(source.contains("Set.of(\"user\", \"admin\", \"service\", \"system\")"));
        assertTrue(source.contains("Set.of(\"not_requested\", \"pending\", \"approved\", \"rejected\", \"suspended\")"));
    }

    @Test
    void protectedRoutesRejectMissingTokensWith401() throws Exception {
        String filter = Files.readString(Path.of("src/main/java/com/microapp/calculator/security/JwtAuthenticationFilter.java"));
        assertTrue(filter.contains("startsWith(\"/v1/\")"));
        assertTrue(filter.contains("Authentication required"));
        assertTrue(filter.contains("HttpStatus.UNAUTHORIZED"));
    }
}
