package com.microapp.calculator.util;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;

public final class SecretRedactor {
    private static final Pattern SECRET_ASSIGNMENT = Pattern.compile("(?i)(authorization|bearer|jwt|token|secret|password|access[_-]?key|secret[_-]?key|credential)(\\s*[=:]\\s*)[^\\s,}]+") ;
    private static final List<String> SENSITIVE_KEYS = List.of("authorization", "jwt", "token", "secret", "password", "access_key", "secret_key", "credential", "refresh_token", "access_token");

    private SecretRedactor() {
    }

    public static String redact(String input) {
        if (input == null) {
            return null;
        }
        return SECRET_ASSIGNMENT.matcher(input).replaceAll("$1$2[REDACTED]");
    }

    @SuppressWarnings("unchecked")
    public static Object sanitize(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof String s) {
            return redact(s);
        }
        if (value instanceof Map<?, ?> map) {
            Map<String, Object> sanitized = new LinkedHashMap<>();
            for (Map.Entry<?, ?> entry : map.entrySet()) {
                String key = String.valueOf(entry.getKey());
                if (isSensitive(key)) {
                    sanitized.put(key, "[REDACTED]");
                } else {
                    sanitized.put(key, sanitize(entry.getValue()));
                }
            }
            return sanitized;
        }
        if (value instanceof Iterable<?> iterable) {
            List<Object> sanitized = new ArrayList<>();
            for (Object item : iterable) {
                sanitized.add(sanitize(item));
            }
            return sanitized;
        }
        return value;
    }

    public static boolean isSensitive(String key) {
        String normalized = key == null ? "" : key.toLowerCase(Locale.ROOT).replace('-', '_');
        return SENSITIVE_KEYS.stream().anyMatch(normalized::contains);
    }
}
