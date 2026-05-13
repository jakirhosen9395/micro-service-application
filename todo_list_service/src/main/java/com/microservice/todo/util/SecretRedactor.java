package com.microservice.todo.util;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class SecretRedactor {
    private static final List<String> SECRET_MARKERS = List.of(
            "password", "secret", "token", "authorization", "jwt", "access_key", "secret_key", "connection", "credential");

    private SecretRedactor() {}

    public static String redact(String value) {
        if (value == null) return null;
        String redacted = value;
        redacted = redacted.replaceAll("(?i)(authorization\\s*[:=]\\s*bearer\\s+)[A-Za-z0-9._\\-]+", "$1[REDACTED]");
        redacted = redacted.replaceAll("(?i)(password|secret|token|jwt|access[_-]?key|secret[_-]?key)(\\s*[:=]\\s*)[^\\s,;]+", "$1$2[REDACTED]");
        return redacted;
    }

    @SuppressWarnings("unchecked")
    public static Object redactObject(Object value) {
        if (value instanceof Map<?, ?> map) {
            Map<String, Object> result = new LinkedHashMap<>();
            for (var entry : map.entrySet()) {
                String key = String.valueOf(entry.getKey());
                result.put(key, isSensitive(key) ? "[REDACTED]" : redactObject(entry.getValue()));
            }
            return result;
        }
        if (value instanceof List<?> list) {
            return list.stream().map(SecretRedactor::redactObject).toList();
        }
        if (value instanceof String text) return redact(text);
        return value;
    }

    public static Map<String, Object> redactMap(Map<String, Object> value) {
        return (Map<String, Object>) redactObject(value == null ? Map.of() : value);
    }

    private static boolean isSensitive(String key) {
        String lower = key == null ? "" : key.toLowerCase(Locale.ROOT);
        return SECRET_MARKERS.stream().anyMatch(lower::contains);
    }
}
