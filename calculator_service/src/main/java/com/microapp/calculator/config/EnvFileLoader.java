package com.microapp.calculator.config;

import java.io.BufferedReader;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;

public final class EnvFileLoader {
    private EnvFileLoader() {
    }

    public static void load() {
        String selected = firstNonBlank(
                System.getProperty("APP_ENV"),
                System.getenv("APP_ENV"),
                System.getProperty("CALC_ENV"),
                System.getenv("CALC_ENV"),
                System.getProperty("CALC_NODE_ENV"),
                System.getenv("CALC_NODE_ENV"),
                "dev"
        );
        String suffix = toFileSuffix(selected);
        Path file = Path.of(".env." + suffix);
        if (!Files.isRegularFile(file)) {
            return;
        }
        try (BufferedReader reader = Files.newBufferedReader(file, StandardCharsets.UTF_8)) {
            String line;
            while ((line = reader.readLine()) != null) {
                parseLine(line);
            }
        } catch (IOException ex) {
            throw new IllegalStateException("Unable to read " + file, ex);
        }
    }

    private static void parseLine(String line) {
        String trimmed = line.trim();
        if (trimmed.isEmpty() || trimmed.startsWith("#") || !trimmed.contains("=")) {
            return;
        }
        int idx = trimmed.indexOf('=');
        String key = trimmed.substring(0, idx).trim();
        String value = trimmed.substring(idx + 1).trim();
        if ((value.startsWith("\"") && value.endsWith("\"")) || (value.startsWith("'") && value.endsWith("'"))) {
            value = value.substring(1, value.length() - 1);
        }
        if (!key.isBlank() && System.getenv(key) == null && System.getProperty(key) == null) {
            System.setProperty(key, value);
        }
    }

    private static String toFileSuffix(String value) {
        String v = value.toLowerCase(Locale.ROOT).trim();
        return switch (v) {
            case "development", "local" -> "dev";
            case "production" -> "prod";
            case "staging" -> "stage";
            default -> v;
        };
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) {
                return value;
            }
        }
        return "dev";
    }
}
