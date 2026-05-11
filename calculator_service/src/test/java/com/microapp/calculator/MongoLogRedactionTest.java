package com.microapp.calculator;

import com.microapp.calculator.util.SecretRedactor;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class MongoLogRedactionTest {
    @SuppressWarnings("unchecked")
    @Test
    void redactsSecretsFromLogMessagesAndStructuredPayloads() {
        String redacted = SecretRedactor.redact("password=hunter2 authorization=Bearer abc secret_key=xyz");
        assertFalse(redacted.contains("hunter2"));
        assertFalse(redacted.contains("Bearer abc"));
        assertFalse(redacted.contains("xyz"));
        Map<String, Object> sanitized = (Map<String, Object>) SecretRedactor.sanitize(Map.of(
                "access_token", "jwt-value",
                "nested", Map.of("password", "secret"),
                "safe", "ok"
        ));
        assertEquals("[REDACTED]", sanitized.get("access_token"));
        assertEquals("ok", sanitized.get("safe"));
        assertTrue(String.valueOf(sanitized.get("nested")).contains("[REDACTED]"));
    }
}
