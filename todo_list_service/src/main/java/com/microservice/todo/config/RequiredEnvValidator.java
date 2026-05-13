package com.microservice.todo.config;

import java.util.ArrayList;
import java.util.List;

public final class RequiredEnvValidator {
    private static final List<String> REQUIRED = List.of(
            "TODO_SERVICE_NAME", "TODO_ENV", "TODO_NODE_ENV", "TODO_VERSION", "TODO_TENANT",
            "TODO_HOST", "TODO_PORT",
            "TODO_JWT_SECRET", "TODO_JWT_ISSUER", "TODO_JWT_AUDIENCE", "TODO_JWT_ALGORITHM", "TODO_JWT_LEEWAY_SECONDS",
            "TODO_POSTGRES_HOST", "TODO_POSTGRES_PORT", "TODO_POSTGRES_USER", "TODO_POSTGRES_PASSWORD", "TODO_POSTGRES_DB", "TODO_POSTGRES_SCHEMA", "TODO_POSTGRES_POOL_SIZE", "TODO_POSTGRES_MAX_OVERFLOW", "TODO_POSTGRES_MIGRATION_MODE",
            "TODO_REDIS_HOST", "TODO_REDIS_PORT", "TODO_REDIS_PASSWORD", "TODO_REDIS_DB", "TODO_REDIS_CACHE_TTL_SECONDS",
            "TODO_KAFKA_BOOTSTRAP_SERVERS", "TODO_KAFKA_EVENTS_TOPIC", "TODO_KAFKA_DEAD_LETTER_TOPIC", "TODO_KAFKA_CONSUMER_GROUP", "TODO_KAFKA_CONSUME_TOPICS", "TODO_KAFKA_AUTO_CREATE_TOPICS",
            "TODO_S3_ENDPOINT", "TODO_S3_ACCESS_KEY", "TODO_S3_SECRET_KEY", "TODO_S3_REGION", "TODO_S3_FORCE_PATH_STYLE", "TODO_S3_BUCKET", "TODO_S3_AUDIT_PREFIX", "TODO_S3_REPORT_PREFIX",
            "TODO_MONGO_HOST", "TODO_MONGO_PORT", "TODO_MONGO_USERNAME", "TODO_MONGO_PASSWORD", "TODO_MONGO_DATABASE", "TODO_MONGO_AUTH_SOURCE", "TODO_MONGO_LOG_COLLECTION",
            "TODO_APM_SERVER_URL", "TODO_APM_SECRET_TOKEN", "TODO_APM_TRANSACTION_SAMPLE_RATE", "TODO_APM_CAPTURE_BODY", "TODO_ELASTICSEARCH_URL", "TODO_ELASTICSEARCH_USERNAME", "TODO_ELASTICSEARCH_PASSWORD", "TODO_KIBANA_URL", "TODO_KIBANA_USERNAME", "TODO_KIBANA_PASSWORD",
            "TODO_LOG_LEVEL", "TODO_LOG_FORMAT", "TODO_LOGSTASH_ENABLED", "TODO_LOGSTASH_HOST", "TODO_LOGSTASH_PORT",
            "TODO_CORS_ALLOWED_ORIGINS", "TODO_CORS_ALLOWED_METHODS", "TODO_CORS_ALLOWED_HEADERS", "TODO_CORS_ALLOW_CREDENTIALS", "TODO_CORS_MAX_AGE_SECONDS",
            "TODO_SECURITY_REQUIRE_HTTPS", "TODO_SECURITY_SECURE_COOKIES", "TODO_SECURITY_REQUIRE_TENANT_MATCH",
            "TODO_OUTBOX_RETRY_DELAY_MS", "TODO_HEALTH_TIMEOUT_SECONDS", "TODO_DEFAULT_PAGE_SIZE", "TODO_MAX_PAGE_SIZE"
    );

    private static final List<String> FORBIDDEN = List.of(
            "TODO_S3_ENABLED", "TODO_KAFKA_ENABLED", "TODO_REDIS_ENABLED", "TODO_POSTGRES_ENABLED",
            "TODO_MONGO_ENABLED", "TODO_APM_ENABLED", "TODO_SWAGGER_ENABLED", "TODO_S3_REQUIRED",
            "TODO_KAFKA_REQUIRED", "TODO_REDIS_REQUIRED", "TODO_POSTGRES_REQUIRED", "TODO_MONGO_REQUIRED",
            "TODO_MONGO_LOGS_ENABLED", "TODO_APM_REQUIRED", "TODO_ELASTICSEARCH_REQUIRED"
    );

    private RequiredEnvValidator() {}

    public static void validate() {
        List<String> forbidden = new ArrayList<>();
        for (String key : FORBIDDEN) {
            if (firstNonBlank(System.getenv(key), System.getProperty(key)) != null) forbidden.add(key);
        }
        if (!forbidden.isEmpty()) {
            throw new IllegalStateException("Forbidden infrastructure toggle keys are not allowed: " + String.join(", ", forbidden));
        }

        List<String> missing = new ArrayList<>();
        for (String key : REQUIRED) {
            String value = firstNonBlank(System.getenv(key), System.getProperty(key));
            if (value == null) missing.add(key);
        }
        if (!missing.isEmpty()) {
            throw new IllegalStateException("Missing required todo_list_service environment keys: " + String.join(", ", missing));
        }
        if (!"todo_list_service".equals(firstNonBlank(System.getenv("TODO_SERVICE_NAME"), System.getProperty("TODO_SERVICE_NAME")))) {
            throw new IllegalStateException("TODO_SERVICE_NAME must be todo_list_service");
        }
        if (!"8080".equals(firstNonBlank(System.getenv("TODO_PORT"), System.getProperty("TODO_PORT")))) {
            throw new IllegalStateException("TODO_PORT must be 8080");
        }
        if (!"false".equalsIgnoreCase(firstNonBlank(System.getenv("TODO_LOGSTASH_ENABLED"), System.getProperty("TODO_LOGSTASH_ENABLED")))) {
            throw new IllegalStateException("TODO_LOGSTASH_ENABLED must be false");
        }
        if (!"microservice".equals(firstNonBlank(System.getenv("TODO_S3_BUCKET"), System.getProperty("TODO_S3_BUCKET")))) {
            throw new IllegalStateException("TODO_S3_BUCKET must be microservice");
        }
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) return value.trim();
        }
        return null;
    }
}
