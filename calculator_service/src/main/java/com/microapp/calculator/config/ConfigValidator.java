package com.microapp.calculator.config;

import com.microapp.calculator.logging.MongoStructuredLogger;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

@Component
@Order(1)
public class ConfigValidator implements ApplicationRunner {
    private static final List<String> REQUIRED = List.of(
            "CALC_SERVICE_NAME", "CALC_ENV", "CALC_NODE_ENV", "CALC_VERSION", "CALC_TENANT",
            "CALC_HOST", "CALC_PORT",
            "CALC_JWT_SECRET", "CALC_JWT_ISSUER", "CALC_JWT_AUDIENCE", "CALC_JWT_ALGORITHM", "CALC_JWT_LEEWAY_SECONDS",
            "CALC_POSTGRES_HOST", "CALC_POSTGRES_PORT", "CALC_POSTGRES_USER", "CALC_POSTGRES_PASSWORD", "CALC_POSTGRES_DB", "CALC_POSTGRES_SCHEMA", "CALC_POSTGRES_POOL_SIZE", "CALC_POSTGRES_MAX_OVERFLOW", "CALC_POSTGRES_MIGRATION_MODE",
            "CALC_REDIS_HOST", "CALC_REDIS_PORT", "CALC_REDIS_PASSWORD", "CALC_REDIS_DB", "CALC_REDIS_CACHE_TTL_SECONDS",
            "CALC_KAFKA_BOOTSTRAP_SERVERS", "CALC_KAFKA_EVENTS_TOPIC", "CALC_KAFKA_DEAD_LETTER_TOPIC", "CALC_KAFKA_CONSUMER_GROUP", "CALC_KAFKA_CONSUME_TOPICS", "CALC_KAFKA_AUTO_CREATE_TOPICS",
            "CALC_S3_ENDPOINT", "CALC_S3_ACCESS_KEY", "CALC_S3_SECRET_KEY", "CALC_S3_REGION", "CALC_S3_FORCE_PATH_STYLE", "CALC_S3_BUCKET", "CALC_S3_AUDIT_PREFIX", "CALC_S3_REPORT_PREFIX",
            "CALC_MONGO_HOST", "CALC_MONGO_PORT", "CALC_MONGO_USERNAME", "CALC_MONGO_PASSWORD", "CALC_MONGO_DATABASE", "CALC_MONGO_AUTH_SOURCE", "CALC_MONGO_LOG_COLLECTION",
            "CALC_APM_SERVER_URL", "CALC_APM_SECRET_TOKEN", "CALC_APM_TRANSACTION_SAMPLE_RATE", "CALC_APM_CAPTURE_BODY", "CALC_ELASTICSEARCH_URL", "CALC_ELASTICSEARCH_USERNAME", "CALC_ELASTICSEARCH_PASSWORD", "CALC_KIBANA_URL", "CALC_KIBANA_USERNAME", "CALC_KIBANA_PASSWORD",
            "CALC_LOG_LEVEL", "CALC_LOG_FORMAT", "CALC_LOGSTASH_ENABLED", "CALC_LOGSTASH_HOST", "CALC_LOGSTASH_PORT",
            "CALC_CORS_ALLOWED_ORIGINS", "CALC_CORS_ALLOWED_METHODS", "CALC_CORS_ALLOWED_HEADERS", "CALC_CORS_ALLOW_CREDENTIALS", "CALC_CORS_MAX_AGE_SECONDS",
            "CALC_SECURITY_REQUIRE_HTTPS", "CALC_SECURITY_SECURE_COOKIES", "CALC_SECURITY_REQUIRE_TENANT_MATCH",
            "CALC_FLYWAY_SCHEMA_HISTORY_TABLE", "CALC_MAX_EXPRESSION_LENGTH", "CALC_HISTORY_DEFAULT_LIMIT", "CALC_HISTORY_MAX_LIMIT"
    );

    private static final List<String> FORBIDDEN_TOGGLES = List.of(
            "CALC_S3_ENABLED", "CALC_KAFKA_ENABLED", "CALC_REDIS_ENABLED", "CALC_POSTGRES_ENABLED",
            "CALC_MONGO_ENABLED", "CALC_APM_ENABLED", "CALC_SWAGGER_ENABLED",
            "CALC_S3_REQUIRED", "CALC_KAFKA_REQUIRED", "CALC_REDIS_REQUIRED", "CALC_POSTGRES_REQUIRED",
            "CALC_MONGO_REQUIRED", "CALC_MONGO_LOGS_ENABLED", "CALC_APM_REQUIRED",
            "CALC_ELASTICSEARCH_REQUIRED"
    );

    private final Environment environment;
    private final AppProperties props;
    private final MongoStructuredLogger mongoLogger;

    public ConfigValidator(Environment environment, AppProperties props, MongoStructuredLogger mongoLogger) {
        this.environment = environment;
        this.props = props;
        this.mongoLogger = mongoLogger;
    }

    @Override
    public void run(ApplicationArguments args) {
        List<String> missing = new ArrayList<>();
        for (String key : REQUIRED) {
            String value = environment.getProperty(key);
            if (value == null || value.isBlank()) {
                missing.add(key);
            }
        }
        for (String forbidden : FORBIDDEN_TOGGLES) {
            if (environment.getProperty(forbidden) != null || System.getenv().containsKey(forbidden)) {
                throw new IllegalStateException("Forbidden infrastructure toggle is configured: " + forbidden);
            }
        }
        if (!"calculator_service".equals(props.getServiceName())) {
            throw new IllegalStateException("CALC_SERVICE_NAME must be calculator_service");
        }
        if (props.getPort() != 8080) {
            throw new IllegalStateException("CALC_PORT must be 8080");
        }
        if (!"HS256".equalsIgnoreCase(props.getJwt().getAlgorithm())) {
            throw new IllegalStateException("Only HS256 is supported for auth_service JWT compatibility");
        }
        if (!"microservice".equals(props.getS3().getBucket())) {
            throw new IllegalStateException("CALC_S3_BUCKET must be microservice");
        }
        if (props.isLogstashEnabled()) {
            throw new IllegalStateException("CALC_LOGSTASH_ENABLED must remain false in this build");
        }
        if (!"pretty-json".equals(props.getLogFormat().toLowerCase(Locale.ROOT))) {
            throw new IllegalStateException("CALC_LOG_FORMAT must be pretty-json");
        }
        if (!missing.isEmpty()) {
            throw new IllegalStateException("Missing required calculator_service environment keys: " + missing);
        }
        mongoLogger.info("application.config.validated", "configuration validated", Map.of("required_key_count", REQUIRED.size()));
    }
}
