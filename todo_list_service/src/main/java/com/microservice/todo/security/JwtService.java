package com.microservice.todo.security;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.microservice.todo.config.TodoProperties;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.stereotype.Service;

@Service
public class JwtService {
    public static class TenantMismatchException extends RuntimeException {}
    private static final Set<String> ALLOWED_ROLES = Set.of("user", "admin", "service", "system");
    private static final Set<String> ALLOWED_ADMIN_STATUSES = Set.of("not_requested", "pending", "approved", "rejected", "suspended");

    private final ObjectMapper objectMapper;
    private final TodoProperties properties;

    public JwtService(ObjectMapper objectMapper, TodoProperties properties) {
        this.objectMapper = objectMapper;
        this.properties = properties;
    }

    public Optional<UserPrincipal> parseAndValidate(String token) {
        try {
            String[] parts = token.split("\\.");
            if (parts.length != 3) return Optional.empty();

            Map<String, Object> header = readJson(parts[0]);
            String algorithm = stringValue(header.get("alg"));
            if (!"HS256".equalsIgnoreCase(algorithm) || !properties.getJwt().getAlgorithm().equalsIgnoreCase(algorithm)) return Optional.empty();

            String secret = properties.getJwt().getSecret();
            if (secret == null || secret.isBlank()) return Optional.empty();

            String signingInput = parts[0] + "." + parts[1];
            String expectedSignature = base64Url(hmacSha256(signingInput, secret));
            if (!MessageDigest.isEqual(expectedSignature.getBytes(StandardCharsets.UTF_8), parts[2].getBytes(StandardCharsets.UTF_8))) return Optional.empty();

            Map<String, Object> claims = readJson(parts[1]);
            if (!validTimeClaims(claims) || !validIssuer(claims) || !validAudience(claims)) return Optional.empty();

            String userId = stringClaim(claims, "sub");
            String jti = stringClaim(claims, "jti");
            if (userId == null || userId.isBlank()) return Optional.empty();
            if (jti == null || jti.isBlank()) return Optional.empty();

            String role = normalize(stringClaim(claims, "role"), "user");
            if (!ALLOWED_ROLES.contains(role)) return Optional.empty();

            String adminStatus = normalize(stringClaim(claims, "admin_status"), "not_requested");
            if (!ALLOWED_ADMIN_STATUSES.contains(adminStatus)) return Optional.empty();

            String tenant = firstNonBlank(stringClaim(claims, "tenant"), properties.getTenant(), "dev");
            if (properties.getSecurity().isRequireTenantMatch() && !tenant.equals(properties.getTenant())) throw new TenantMismatchException();

            return Optional.of(new UserPrincipal(
                    userId,
                    stringClaim(claims, "username"),
                    stringClaim(claims, "email"),
                    tenant,
                    role,
                    adminStatus,
                    claims));
        } catch (TenantMismatchException ex) {
            throw ex;
        } catch (Exception ex) {
            return Optional.empty();
        }
    }

    private boolean validTimeClaims(Map<String, Object> claims) {
        long now = Instant.now().getEpochSecond();
        long leeway = Math.max(0, properties.getJwt().getLeewaySeconds());
        Number exp = numberClaim(claims, "exp");
        if (exp == null || now > exp.longValue() + leeway) return false;
        Number nbf = numberClaim(claims, "nbf");
        if (nbf != null && now + leeway < nbf.longValue()) return false;
        Number iat = numberClaim(claims, "iat");
        return iat == null || now + leeway >= iat.longValue();
    }

    private boolean validIssuer(Map<String, Object> claims) {
        String expected = properties.getJwt().getIssuer();
        return expected == null || expected.isBlank() || expected.equals(stringClaim(claims, "iss"));
    }

    private boolean validAudience(Map<String, Object> claims) {
        String expected = properties.getJwt().getAudience();
        if (expected == null || expected.isBlank()) return true;
        Object aud = claims.get("aud");
        if (aud instanceof String value) return expected.equals(value);
        if (aud instanceof List<?> values) return values.stream().map(String::valueOf).anyMatch(expected::equals);
        return false;
    }

    private Number numberClaim(Map<String, Object> claims, String key) {
        Object value = claims.get(key);
        return value instanceof Number number ? number : null;
    }

    private String stringClaim(Map<String, Object> claims, String key) {
        return stringValue(claims.get(key));
    }

    private String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private String normalize(String value, String defaultValue) {
        return value == null || value.isBlank() ? defaultValue : value.toLowerCase(Locale.ROOT);
    }

    private String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) return value.trim();
        }
        return "dev";
    }

    private Map<String, Object> readJson(String encoded) throws Exception {
        byte[] bytes = Base64.getUrlDecoder().decode(encoded);
        return objectMapper.readValue(bytes, new TypeReference<>() {});
    }

    private byte[] hmacSha256(String data, String secret) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        return mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
    }

    private String base64Url(byte[] bytes) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
}
