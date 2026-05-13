package com.microservice.todo.config;

import co.elastic.apm.attach.ElasticApmAttacher;

import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

public final class ElasticApmBootstrap {
    private static final AtomicBoolean ATTACHED = new AtomicBoolean(false);
    private static final String APPLICATION_PACKAGES = "com.microservice.todo";

    private ElasticApmBootstrap() {
    }

    public static void attachFromEnvironment() {
        Map<String, String> config = baseConfig(
                env("TODO_SERVICE_NAME", "ELASTIC_APM_SERVICE_NAME", "todo_list_service"),
                env("TODO_VERSION", "ELASTIC_APM_SERVICE_VERSION", "v1.0.0"),
                displayEnvironment(env("TODO_ENV", "ELASTIC_APM_ENVIRONMENT", "development")),
                env("TODO_APM_SERVER_URL", "ELASTIC_APM_SERVER_URL", ""),
                env("TODO_APM_SECRET_TOKEN", "ELASTIC_APM_SECRET_TOKEN", ""),
                env("TODO_APM_TRANSACTION_SAMPLE_RATE", "ELASTIC_APM_TRANSACTION_SAMPLE_RATE", "1.0"),
                env("TODO_APM_CAPTURE_BODY", "ELASTIC_APM_CAPTURE_BODY", "errors"),
                env("TODO_TENANT", null, "dev")
        );
        attach(config);
    }

    public static void attach(TodoProperties properties) {
        Map<String, String> config = baseConfig(
                properties.getServiceName(),
                properties.getServiceVersion(),
                displayEnvironment(properties.getEnv()),
                properties.getApm().getServerUrl(),
                properties.getApm().getSecretToken(),
                properties.getApm().getTransactionSampleRate(),
                properties.getApm().getCaptureBody(),
                properties.getTenant()
        );
        attach(config);
    }

    private static Map<String, String> baseConfig(
            String serviceName,
            String serviceVersion,
            String environment,
            String serverUrl,
            String secretToken,
            String transactionSampleRate,
            String captureBody,
            String tenant
    ) {
        Map<String, String> config = new HashMap<>();
        config.put("service_name", serviceName);
        config.put("service_version", stripVersionPrefix(serviceVersion));
        config.put("environment", environment);
        config.put("server_url", serverUrl);
        config.put("transaction_sample_rate", transactionSampleRate);
        config.put("capture_body", captureBody);
        config.put("application_packages", APPLICATION_PACKAGES);
        config.put("capture_headers", "true");
        config.put("central_config", "true");
        config.put("breakdown_metrics", "true");
        config.put("metrics_interval", "30s");
        config.put("span_min_duration", "0ms");
        config.put("log_level", "ERROR");
        config.put("global_labels", "tenant=" + safeLabel(tenant) + ",service=" + safeLabel(serviceName));
        config.put("sanitize_field_names", "password,passwd,pwd,*secret*,*token*,*key*,authorization,cookie,set-cookie,jwt,session,credit,card");
        if (secretToken != null && !secretToken.isBlank()) {
            config.put("secret_token", secretToken);
        }
        return config;
    }

    private static void attach(Map<String, String> config) {
        String serverUrl = config.get("server_url");
        if (serverUrl == null || serverUrl.isBlank() || !ATTACHED.compareAndSet(false, true)) {
            return;
        }
        try {
            ElasticApmAttacher.attach(config);
        } catch (Throwable ex) {
            ATTACHED.set(false);
            System.err.println("Elastic APM attach skipped: " + ex.getClass().getSimpleName());
        }
    }

    private static String env(String primary, String secondary, String fallback) {
        String value = System.getenv(primary);
        if (value == null || value.isBlank()) {
            value = secondary == null ? null : System.getenv(secondary);
        }
        return value == null || value.isBlank() ? fallback : value.trim();
    }

    private static String displayEnvironment(String env) {
        return switch ((env == null ? "" : env).toLowerCase(Locale.ROOT)) {
            case "dev", "development" -> "development";
            case "stage", "staging" -> "stage";
            case "prod", "production" -> "production";
            default -> env == null || env.isBlank() ? "development" : env;
        };
    }

    private static String stripVersionPrefix(String version) {
        if (version == null || version.isBlank()) {
            return "1.0.0";
        }
        return version.replaceFirst("^[vV]", "");
    }

    private static String safeLabel(String value) {
        return value == null ? "unknown" : value.replace(",", "_").replace("=", "_");
    }
}
