package com.microapp.calculator;

import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class EnvContractTest {
    private static final List<String> EXPECTED_ORDER = List.of(
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

    private static final Set<String> FORBIDDEN = Set.of(
            "CALC_S3_ENABLED", "CALC_KAFKA_ENABLED", "CALC_REDIS_ENABLED", "CALC_POSTGRES_ENABLED",
            "CALC_MONGO_ENABLED", "CALC_APM_ENABLED", "CALC_SWAGGER_ENABLED",
            "CALC_S3_REQUIRED", "CALC_KAFKA_REQUIRED", "CALC_REDIS_REQUIRED", "CALC_POSTGRES_REQUIRED",
            "CALC_MONGO_REQUIRED", "CALC_MONGO_LOGS_ENABLED", "CALC_APM_REQUIRED", "CALC_ELASTICSEARCH_REQUIRED"
    );

    @Test
    void allEnvFilesHaveTheSameKeysInTheSameOrder() throws Exception {
        List<String> expected = keys(".env.dev");
        assertEquals(EXPECTED_ORDER, expected);
        assertEquals(expected, keys(".env.stage"));
        assertEquals(expected, keys(".env.prod"));
        assertEquals(expected, keys(".env.example"));
    }

    @Test
    void runtimeJwtSecretIsConfiguredForSharedAuthServiceTokens() throws Exception {
        String dev = value(".env.dev", "CALC_JWT_SECRET");
        String stage = value(".env.stage", "CALC_JWT_SECRET");
        String prod = value(".env.prod", "CALC_JWT_SECRET");

        assertEquals(dev, stage);
        assertEquals(dev, prod);
        assertTrue(dev.length() >= 64);
        assertFalse(dev.contains("change-me"));
        assertFalse(dev.contains("your-jwt-secret"));
    }

    @Test
    void fixedValuesAndForbiddenInfrastructureTogglesAreCorrect() throws Exception {
        String content = Files.readString(Path.of(".env.dev"));
        assertTrue(content.contains("CALC_SERVICE_NAME=calculator_service"));
        assertTrue(content.contains("CALC_PORT=8080"));
        assertTrue(content.contains("CALC_JWT_ISSUER=auth"));
        assertTrue(content.contains("CALC_JWT_AUDIENCE=micro-app"));
        assertTrue(content.contains("CALC_JWT_ALGORITHM=HS256"));
        assertTrue(content.contains("CALC_POSTGRES_SCHEMA=calculator"));
        assertTrue(content.contains("CALC_KAFKA_EVENTS_TOPIC=calculator.events"));
        assertTrue(content.contains("CALC_KAFKA_DEAD_LETTER_TOPIC=calculator.dead-letter"));
        assertTrue(content.contains("CALC_S3_BUCKET=microservice"));
        assertTrue(content.contains("CALC_LOG_FORMAT=pretty-json"));
        assertTrue(content.contains("CALC_LOGSTASH_ENABLED=false"));
        assertTrue(content.contains("CALC_FLYWAY_SCHEMA_HISTORY_TABLE=calculator_service_flyway_schema_history"));
        for (String file : List.of(".env.dev", ".env.stage", ".env.prod", ".env.example")) {
            List<String> envKeys = keys(file);
            for (String forbidden : FORBIDDEN) {
                assertFalse(envKeys.contains(forbidden), file + " must not contain " + forbidden);
            }
        }
    }


    private static String value(String file, String key) throws Exception {
        return Files.readAllLines(Path.of(file)).stream()
                .map(String::trim)
                .filter(line -> line.startsWith(key + "="))
                .map(line -> line.substring(line.indexOf('=') + 1))
                .findFirst()
                .orElseThrow(() -> new AssertionError("Missing key " + key + " in " + file));
    }

    private static List<String> keys(String file) throws Exception {
        return Files.readAllLines(Path.of(file)).stream()
                .map(String::trim)
                .filter(line -> !line.isBlank() && !line.startsWith("#") && line.contains("="))
                .map(line -> line.substring(0, line.indexOf('=')))
                .toList();
    }
}
