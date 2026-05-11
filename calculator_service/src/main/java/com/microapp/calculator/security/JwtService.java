package com.microapp.calculator.security;

import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.exception.ApiException;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jws;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Collection;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

@Service
public class JwtService {
    private static final Set<String> ROLES = Set.of("user", "admin", "service", "system");
    private static final Set<String> ADMIN_STATUSES = Set.of("not_requested", "pending", "approved", "rejected", "suspended");
    private final AppProperties props;
    private final SecretKey key;

    public JwtService(AppProperties props) {
        this.props = props;
        this.key = Keys.hmacShaKeyFor(props.getJwt().getSecret().getBytes(StandardCharsets.UTF_8));
    }

    public UserPrincipal validate(String token) {
        if (token == null || token.isBlank()) {
            throw unauthorized("Authentication required");
        }
        try {
            Jws<Claims> parsed = Jwts.parser()
                    .verifyWith(key)
                    .clockSkewSeconds(props.getJwt().getLeewaySeconds())
                    .requireIssuer(props.getJwt().getIssuer())
                    .build()
                    .parseSignedClaims(token);
            if (!"HS256".equals(parsed.getHeader().getAlgorithm())) {
                throw unauthorized("Invalid token algorithm");
            }
            Claims claims = parsed.getPayload();

            requireAudience(claims);
            requireTemporalClaims(claims);
            String subject = requiredString(claims, "sub");
            String jti = requiredString(claims, "jti");
            String username = requiredString(claims, "username");
            String email = requiredString(claims, "email");
            String role = requiredString(claims, "role").toLowerCase(Locale.ROOT);
            String adminStatus = requiredString(claims, "admin_status").toLowerCase(Locale.ROOT);
            String tenant = requiredString(claims, "tenant");
            if (!ROLES.contains(role)) {
                throw unauthorized("Invalid token role");
            }
            if (!ADMIN_STATUSES.contains(adminStatus)) {
                throw unauthorized("Invalid token admin_status");
            }
            if (props.isSecurityRequireTenantMatch() && !props.getTenant().equals(tenant)) {
                throw new ApiException(HttpStatus.FORBIDDEN, "TENANT_MISMATCH", "Token tenant does not match service tenant");
            }
            return new UserPrincipal(subject, jti, username, email, role, adminStatus, tenant);
        } catch (ApiException ex) {
            throw ex;
        } catch (JwtException | IllegalArgumentException ex) {
            throw unauthorized("Invalid or expired token");
        }
    }

    private void requireAudience(Claims claims) {
        Object aud = claims.get("aud");
        boolean ok = false;
        if (aud instanceof String s) {
            ok = props.getJwt().getAudience().equals(s);
        } else if (aud instanceof Collection<?> values) {
            ok = values.stream().anyMatch(v -> props.getJwt().getAudience().equals(String.valueOf(v)));
        }
        if (!ok) {
            throw unauthorized("Invalid token audience");
        }
    }

    private static void requireTemporalClaims(Claims claims) {
        if (claims.getIssuedAt() == null) {
            throw unauthorized("Missing required JWT claim: iat");
        }
        if (claims.getNotBefore() == null) {
            throw unauthorized("Missing required JWT claim: nbf");
        }
        if (claims.getExpiration() == null) {
            throw unauthorized("Missing required JWT claim: exp");
        }
    }

    private static String requiredString(Claims claims, String key) {
        Object value = claims.get(key);
        if (value == null || String.valueOf(value).isBlank()) {
            throw unauthorized("Missing required JWT claim: " + key);
        }
        return String.valueOf(value);
    }

    private static ApiException unauthorized(String message) {
        return new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", message, Map.of());
    }
}
