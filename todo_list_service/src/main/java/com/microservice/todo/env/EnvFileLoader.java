package com.microservice.todo.env;

import java.io.BufferedReader;
import java.io.IOException;
import java.net.URISyntaxException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;

public final class EnvFileLoader {
    private EnvFileLoader() {}

    public static void load(String[] args) {
        String env = normalizeEnv(getArg(args, "--env=")
                .or(() -> Optional.ofNullable(System.getenv("TODO_ENV")))
                .orElse("dev"));
        String explicitPath = getArg(args, "--env-file=")
                .or(() -> Optional.ofNullable(System.getenv("TODO_ENV_FILE")))
                .orElse(null);

        if (explicitPath != null && !explicitPath.isBlank()) {
            loadPath(Path.of(explicitPath));
        } else {
            loadFirstExisting(".env." + env, ".env");
        }

        System.setProperty("TODO_ENV", displayEnv(env));
        System.setProperty("TODO_NODE_ENV", displayEnv(env));
        if (!System.getProperties().containsKey("spring.profiles.active")) {
            System.setProperty("spring.profiles.active", env);
        }
    }

    private static Optional<String> getArg(String[] args, String prefix) {
        if (args == null) return Optional.empty();
        return Arrays.stream(args)
                .filter(a -> a != null && a.startsWith(prefix))
                .map(a -> a.substring(prefix.length()))
                .findFirst();
    }

    private static void loadFirstExisting(String... filenames) {
        for (Path base : candidateRoots()) {
            for (String filename : filenames) {
                Path candidate = base.resolve(filename).normalize();
                if (Files.exists(candidate)) {
                    loadPath(candidate);
                    return;
                }
            }
        }
    }

    private static List<Path> candidateRoots() {
        Path cwd = Path.of(System.getProperty("user.dir", ".")).toAbsolutePath().normalize();
        Path code = codeSourceRoot();
        return List.of(cwd, cwd.getParent() == null ? cwd : cwd.getParent(), code, code.getParent() == null ? code : code.getParent());
    }

    private static Path codeSourceRoot() {
        try {
            Path location = Path.of(EnvFileLoader.class.getProtectionDomain().getCodeSource().getLocation().toURI()).toAbsolutePath().normalize();
            return Files.isRegularFile(location) ? location.getParent() : location;
        } catch (URISyntaxException | RuntimeException ex) {
            return Path.of(System.getProperty("user.dir", ".")).toAbsolutePath().normalize();
        }
    }

    private static void loadPath(Path path) {
        if (!Files.exists(path)) {
            throw new IllegalArgumentException("Env file does not exist: " + path.toAbsolutePath());
        }
        try (BufferedReader reader = Files.newBufferedReader(path)) {
            String line;
            while ((line = reader.readLine()) != null) {
                String trimmed = line.trim();
                if (trimmed.isBlank() || trimmed.startsWith("#") || !trimmed.contains("=")) continue;
                int idx = trimmed.indexOf('=');
                String key = trimmed.substring(0, idx).trim();
                String value = trimmed.substring(idx + 1).trim();
                if ((value.startsWith("\"") && value.endsWith("\"")) || (value.startsWith("'") && value.endsWith("'"))) {
                    value = value.substring(1, value.length() - 1);
                }
                if (System.getenv(key) == null && System.getProperty(key) == null) {
                    System.setProperty(key, value);
                }
            }
        } catch (IOException ex) {
            throw new IllegalStateException("Failed to load env file: " + path.toAbsolutePath(), ex);
        }
    }

    private static String normalizeEnv(String env) {
        return switch (env == null ? "" : env.toLowerCase()) {
            case "development" -> "dev";
            case "staging" -> "stage";
            case "production" -> "prod";
            case "stage", "prod" -> env.toLowerCase();
            default -> "dev";
        };
    }

    private static String displayEnv(String env) {
        return switch (env) {
            case "stage" -> "stage";
            case "prod" -> "production";
            default -> "development";
        };
    }
}
