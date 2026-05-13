#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN_ENV_KEYS = [
    "TODO_S3_ENABLED", "TODO_KAFKA_ENABLED", "TODO_REDIS_ENABLED", "TODO_POSTGRES_ENABLED",
    "TODO_MONGO_ENABLED", "TODO_APM_ENABLED", "TODO_SWAGGER_ENABLED", "TODO_S3_REQUIRED",
    "TODO_KAFKA_REQUIRED", "TODO_REDIS_REQUIRED", "TODO_POSTGRES_REQUIRED", "TODO_MONGO_REQUIRED",
    "TODO_MONGO_LOGS_ENABLED", "TODO_APM_REQUIRED", "TODO_ELASTICSEARCH_REQUIRED",
]
EXPECTED_ENV_KEYS = [
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
    "TODO_OUTBOX_RETRY_DELAY_MS", "TODO_HEALTH_TIMEOUT_SECONDS", "TODO_DEFAULT_PAGE_SIZE", "TODO_MAX_PAGE_SIZE",
]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

def env_keys(path):
    keys = []
    for line in read(path).splitlines():
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            keys.append(line.split("=", 1)[0])
    return keys

def assert_true(condition, message):
    if not condition:
        raise AssertionError(message)

def check_env_contract():
    files = [".env.dev", ".env.stage", ".env.prod", ".env.example"]
    base = env_keys(files[0])
    assert_true(base == EXPECTED_ENV_KEYS, ".env.dev key order does not match canonical TODO order")
    for file in files[1:]:
        assert_true(env_keys(file) == base, f"{file} keys/order differ from .env.dev")
    for file in files:
        text = read(file)
        assert_true("TODO_LOGSTASH_ENABLED=false" in text, f"TODO_LOGSTASH_ENABLED=false missing in {file}")
        for key in FORBIDDEN_ENV_KEYS:
            assert_true(key not in env_keys(file), f"forbidden key {key} found in {file}")


def check_build_contract():
    gradle = read("build.gradle")
    wrapper = read("gradle/wrapper/gradle-wrapper.properties")
    assert_true("org.springframework.boot' version '4.0.6'" in gradle, "Spring Boot Gradle plugin must be 4.0.6")
    assert_true("JavaLanguageVersion.of(25)" in gradle, "Java toolchain must be 25")
    assert_true("spring-boot-starter-actuator" not in gradle, "Actuator starter must not be exposed/required")
    for dep in ["spring-boot-starter-web", "spring-boot-starter-validation", "spring-boot-starter-security", "spring-kafka", "flyway-core", "software.amazon.awssdk:s3", "apm-agent-attach", "jjwt-api", "springdoc-openapi-starter-webmvc-ui"]:
        assert_true(dep in gradle, f"required dependency {dep} missing")
    assert_true("gradle-9.5.0-bin.zip" in wrapper, "Gradle wrapper must be 9.5.0")


def check_application_config():
    text = read("src/main/resources/application.yml")
    assert_true("todo_list_service" in text, "canonical service name missing")
    assert_true("throw-exception-if-no-handler-found: true" in text, "unmapped routes should be handled as 404")
    assert_true("add-mappings: false" in text, "static resource mappings should be disabled")
    assert_true("api-docs:\n    enabled: false" in text, "springdoc api-docs must be disabled")
    assert_true("swagger-ui:\n    enabled: false" in text, "springdoc swagger-ui must be disabled")
    for key in FORBIDDEN_ENV_KEYS:
        assert_true(key not in text, f"forbidden infrastructure gate {key} referenced in application.yml")


def check_public_routes_and_security():
    security = read("src/main/java/com/microservice/todo/security/SecurityConfig.java")
    jwt_filter = read("src/main/java/com/microservice/todo/security/JwtAuthenticationFilter.java")
    assert_true('securityMatcher("/v1/**")' in security, "/v1/** must be the authenticated chain")
    assert_true('securityMatcher("/hello", "/health", "/docs")' in security, "only /hello /health /docs should be public chain")
    for forbidden in ['"/", "/live", "/ready", "/healthy"', '"/actuator', '"/v3/api-docs', '"/swagger-ui']:
        assert_true(forbidden not in security, f"forbidden public matcher {forbidden} found")
    assert_true('"OPTIONS".equalsIgnoreCase(request.getMethod())' in jwt_filter, "CORS preflight must bypass JWT filter")
    assert_true('TENANT_MISMATCH' in jwt_filter, "tenant mismatch must be distinguishable as 403")


def check_migration():
    text = read("src/main/resources/db/migration/V1__todo_list_service_schema.sql").lower()
    for token in [
        "create schema if not exists todo",
        "create table if not exists todos",
        "create table if not exists todo_history",
        "changes jsonb not null default '{}'::jsonb",
        "payload jsonb not null default '{}'::jsonb",
        "create table if not exists outbox_events",
        "id uuid primary key default gen_random_uuid()",
        "create table if not exists kafka_inbox_events",
        "create table if not exists access_grant_projections",
        "unique index if not exists idx_kafka_inbox_topic_partition_offset",
        "idx_access_grants_lookup",
    ]:
        assert_true(token in text, f"migration missing {token}")
    assert_true("public." not in text, "migration must not create public schema objects")


def check_docker_and_commands():
    dockerfile = read("Dockerfile")
    command = read("command.sh")
    assert_true("FROM gradle:9.5.0-jdk25 AS build" in dockerfile, "Docker build stage must use Gradle 9.5.0 + JDK 25")
    assert_true("FROM eclipse-temurin:25-jre" in dockerfile, "Docker runtime must use Java 25 runtime")
    assert_true("EXPOSE 8080" in dockerfile and "EXPOSE " not in dockerfile.replace("EXPOSE 8080", ""), "Dockerfile must expose only 8080")
    assert_true("USER appuser" in dockerfile, "Dockerfile must run as non-root appuser")
    assert_true("/hello" in dockerfile, "Docker healthcheck must use /hello")
    assert_true('ENTRYPOINT ["java"' in dockerfile and '"-jar", "/app/app.jar"' in dockerfile, "Docker entrypoint must run app.jar")
    assert_true(command.startswith("#!/usr/bin/env sh"), "command.sh must use sh")
    for token in ["todo_list_service:latest", "todo_list_service:dev", "todo_list_service:stage", "todo_list_service:prod", "-p 3030:8080", "-p 3031:8080", "-p 3032:8080"]:
        assert_true(token in command, f"command.sh missing {token}")
    assert_true("$1" not in command and "function " not in command and "curl " not in command, "command.sh must not use dynamic args, helper functions, or smoke-test curls")


def check_s3_redis_kafka_contracts():
    s3 = read("src/main/java/com/microservice/todo/service/S3AuditService.java")
    redis = read("src/main/java/com/microservice/todo/service/TodoCacheService.java")
    kafka = read("src/main/java/com/microservice/todo/service/TodoEventPublisher.java")
    inbox = read("src/main/java/com/microservice/todo/service/KafkaInboxConsumer.java")
    assert_true("/tenant/%s/users/%s/events/%s/%s_%s_%s.json" in s3, "S3 audit key format is not canonical")
    assert_true("SecretRedactor.redactMap" in s3, "S3 audit payload must be redacted")
    for token in ["record:", "list:", "today:", "overdue:", "history:"]:
        assert_true(token in redis, f"Redis key namespace/cache pattern {token} missing")
    for header in ['"event_id"', '"event_type"', '"service"', '"tenant"', '"trace_id"', '"correlation_id"']:
        assert_true(header in kafka, f"Kafka header {header} missing")
    assert_true("event.tenant() + \":\" + event.userId()" in kafka, "Kafka key must use tenant:user_id")
    for token in ["access.grant.created", "access.grant.revoked", "access.request.approved", "repository.existsByEventId", "InboxStatus.IGNORED"]:
        assert_true(token in inbox, f"Kafka inbox projection/idempotency missing {token}")


def check_health_contract():
    text = read("src/main/java/com/microservice/todo/health/HealthService.java")
    for key in ['"jwt"', '"postgres"', '"redis"', '"kafka"', '"s3"', '"mongodb"', '"apm"', '"elasticsearch"']:
        assert_true(key in text, f"health dependency key {key} missing")
    dep = read("src/main/java/com/microservice/todo/dto/DependencyStatus.java")
    assert_true('@JsonProperty("latency_ms")' in dep, "dependency latency_ms JSON property missing")
    assert_true('@JsonProperty("error_code")' in dep, "dependency error_code JSON property missing")


def check_response_envelopes():
    api = read("src/main/java/com/microservice/todo/dto/ApiResponse.java")
    error = read("src/main/java/com/microservice/todo/dto/ErrorResponse.java")
    for token in ['String status', 'String message', 'T data', '@JsonProperty("request_id")', '@JsonProperty("trace_id")', 'Instant timestamp']:
        assert_true(token in api, f"success envelope missing {token}")
    for token in ['String status', 'String message', '@JsonProperty("error_code")', 'Map<String, Object> details', 'String path', '@JsonProperty("request_id")', '@JsonProperty("trace_id")', 'Instant timestamp']:
        assert_true(token in error, f"error envelope missing {token}")


def check_docs_contract():
    docs = read("src/main/java/com/microservice/todo/controller/DocsController.java")
    assert_true('@GetMapping(value = "/docs"' in docs, "/docs endpoint missing")
    for token in ["Todo List Service API Console", "bearerAuth", "persistAuthorization", "requestInterceptor", "tryItOutEnabled", "displayRequestDuration", "PostgreSQL", "Redis", "Kafka", "S3", "MongoDB", "APM"]:
        assert_true(token in docs, f"docs missing {token}")
    for path in ["/v1/todos", "/v1/todos/overdue", "/v1/todos/today", "/v1/todos/{id}/hard"]:
        assert_true(path in docs, f"docs missing {path}")


def check_event_domain_contract():
    event = read("src/main/java/com/microservice/todo/dto/TodoEvent.java")
    service = read("src/main/java/com/microservice/todo/service/TodoService.java")
    for field in ['event_id', 'event_type', 'event_version', 'request_id', 'trace_id', 'correlation_id', 'user_id', 'actor_id', 'aggregate_type', 'aggregate_id']:
        assert_true(field in event, f"event envelope missing {field}")
    for event_type in ["todo.created", "todo.updated", "todo.status_changed", "todo.completed", "todo.archived", "todo.restored", "todo.deleted", "todo.hard_deleted", "todo.audit.s3_written", "todo.audit.s3_failed"]:
        assert_true(event_type in service, f"TodoService missing outgoing event {event_type}")
    assert_true("TODO_INVALID_STATUS_TRANSITION" in read("src/main/java/com/microservice/todo/exception/ApiException.java"), "invalid transition error code missing")
    assert_true("HttpStatus.CONFLICT" in read("src/main/java/com/microservice/todo/exception/ApiException.java"), "invalid transition must return 409")


def check_mongo_logging_contract():
    init = read("src/main/java/com/microservice/todo/health/DependencyInitializer.java")
    for field in ['timestamp', 'level', 'event', 'request_id', 'trace_id', 'user_id', 'path', 'status_code', 'error_code']:
        assert_true(field in init, f"Mongo log index for {field} missing")
    logger = read("src/main/java/com/microservice/todo/service/MongoLogService.java")
    for field in ['timestamp', 'level', 'service', 'version', 'environment', 'tenant', 'logger', 'event', 'message', 'request_id', 'trace_id', 'correlation_id', 'user_id', 'actor_id', 'method', 'path', 'status_code', 'duration_ms', 'client_ip', 'user_agent', 'dependency', 'error_code', 'exception_class', 'exception_message', 'stack_trace', 'host', 'extra']:
        assert_true(field in logger, f"Mongo log document field {field} missing")
    assert_true("SecretRedactor.redactMap" in logger, "Mongo log payloads must be redacted")


def main():
    checks = [
        check_env_contract,
        check_build_contract,
        check_application_config,
        check_public_routes_and_security,
        check_response_envelopes,
        check_health_contract,
        check_docs_contract,
        check_migration,
        check_event_domain_contract,
        check_mongo_logging_contract,
        check_docker_and_commands,
        check_s3_redis_kafka_contracts,
    ]
    for check in checks:
        check()
        print(f"[OK] {check.__name__}")
    print("All static contract checks passed.")

if __name__ == "__main__":
    try:
        main()
    except AssertionError as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        sys.exit(1)
