package com.microservice.todo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.Test;

class ContractStaticTest {
    private static final Path ROOT = Path.of(System.getProperty("user.dir"));
    private static final List<String> FORBIDDEN = List.of(
            "TODO_S3_ENABLED", "TODO_KAFKA_ENABLED", "TODO_REDIS_ENABLED", "TODO_POSTGRES_ENABLED",
            "TODO_MONGO_ENABLED", "TODO_MONGO_LOGS_ENABLED", "TODO_APM_ENABLED", "TODO_SWAGGER_ENABLED",
            "TODO_S3_REQUIRED", "TODO_KAFKA_REQUIRED", "TODO_REDIS_REQUIRED", "TODO_POSTGRES_REQUIRED",
            "TODO_MONGO_REQUIRED", "TODO_APM_REQUIRED", "TODO_ELASTICSEARCH_REQUIRED");

    @Test
    void envFilesHaveIdenticalKeysInSameOrderAndNoForbiddenToggles() throws IOException {
        List<String> dev = keys(".env.dev");
        assertEquals(dev, keys(".env.stage"));
        assertEquals(dev, keys(".env.prod"));
        assertEquals(dev, keys(".env.example"));
        assertTrue(dev.contains("TODO_LOGSTASH_ENABLED"));
        for (String file : List.of(".env.dev", ".env.stage", ".env.prod", ".env.example")) {
            String text = read(file);
            assertTrue(text.contains("TODO_LOGSTASH_ENABLED=false"));
            for (String key : FORBIDDEN) assertFalse(keys(file).contains(key), key + " must not be present in " + file);
        }
    }

    @Test
    void buildUsesJava25SpringBoot4AndGradle95() throws IOException {
        String gradle = read("build.gradle");
        String wrapper = read("gradle/wrapper/gradle-wrapper.properties");
        assertTrue(gradle.contains("org.springframework.boot' version '4.0.6'"));
        assertTrue(gradle.contains("JavaLanguageVersion.of(25)"));
        assertTrue(gradle.contains("spring-kafka"));
        assertTrue(gradle.contains("software.amazon.awssdk:s3"));
        assertTrue(gradle.contains("apm-agent-attach"));
        assertTrue(gradle.contains("jjwt-api"));
        assertTrue(gradle.contains("springdoc-openapi-starter-webmvc-ui"));
        assertFalse(gradle.contains("spring-boot-starter-actuator"));
        assertTrue(read("src/main/java/com/microservice/todo/TodoListServiceApplication.java").contains("ElasticApmBootstrap.attachFromEnvironment()"));
        assertTrue(read("src/main/java/com/microservice/todo/config/ElasticApmBootstrap.java").contains("metrics_interval"));
        assertTrue(read("src/main/java/com/microservice/todo/config/ElasticApmBootstrap.java").contains("breakdown_metrics"));
        assertTrue(wrapper.contains("gradle-9.5.0-bin.zip"));
    }

    @Test
    void dockerAndCommandContractsAreCanonical() throws IOException {
        String dockerfile = read("Dockerfile");
        String command = read("command.sh");
        assertTrue(dockerfile.contains("FROM gradle:9.5.0-jdk25 AS build"));
        assertTrue(dockerfile.contains("FROM eclipse-temurin:25-jre"));
        assertTrue(dockerfile.contains("EXPOSE 8080"));
        assertTrue(dockerfile.contains("USER appuser"));
        assertTrue(dockerfile.contains("/hello"));
        assertTrue(command.startsWith("#!/usr/bin/env sh"));
        for (String token : List.of("todo_list_service:latest", "todo_list_service:dev", "todo_list_service:stage", "todo_list_service:prod", "-p 3030:8080", "-p 3031:8080", "-p 3032:8080")) {
            assertTrue(command.contains(token), token);
        }
        assertFalse(command.contains("$1"));
        assertFalse(command.contains("curl "));
    }

    @Test
    void securityAndRouteContractIsStrict() throws IOException {
        String security = read("src/main/java/com/microservice/todo/security/SecurityConfig.java");
        String application = read("src/main/resources/application.yml");
        assertTrue(security.contains("securityMatcher(\"/v1/**\")"));
        assertTrue(security.contains("securityMatcher(\"/hello\", \"/health\", \"/docs\")"));
        assertFalse(security.contains("\"/\", \"/live\", \"/ready\", \"/healthy\""));
        assertTrue(application.contains("throw-exception-if-no-handler-found: true"));
        assertTrue(application.contains("add-mappings: false"));
        assertTrue(application.contains("api-docs:\n    enabled: false"));
        assertTrue(application.contains("swagger-ui:\n    enabled: false"));
    }

    @Test
    void migrationContainsCanonicalTodoOutboxInboxAndGrantProjection() throws IOException {
        String sql = read("src/main/resources/db/migration/V1__todo_list_service_schema.sql").toLowerCase();
        for (String token : List.of(
                "create schema if not exists todo",
                "create table if not exists todos",
                "create table if not exists todo_history",
                "changes jsonb not null default '{}'::jsonb",
                "payload jsonb not null default '{}'::jsonb",
                "create table if not exists outbox_events",
                "id uuid primary key default gen_random_uuid()",
                "create table if not exists kafka_inbox_events",
                "create table if not exists access_grant_projections",
                "idx_kafka_inbox_topic_partition_offset",
                "idx_access_grants_lookup")) {
            assertTrue(sql.contains(token), token);
        }
        assertFalse(sql.contains("public."));
    }

    @Test
    void docsAreEmbeddedAndInteractive() throws IOException {
        String docs = read("src/main/java/com/microservice/todo/controller/DocsController.java");
        for (String token : List.of("Todo List Service API Console", "bearerAuth", "persistAuthorization", "tryItOutEnabled", "requestInterceptor", "PostgreSQL", "Redis", "Kafka", "S3", "MongoDB", "APM")) {
            assertTrue(docs.contains(token), token);
        }
        for (String path : List.of("/v1/todos", "/v1/todos/overdue", "/v1/todos/today", "/v1/todos/{id}/history", "/v1/todos/{id}/hard")) {
            assertTrue(docs.contains(path), path);
        }
    }

    @Test
    void eventCacheS3AndMongoContractsArePresent() throws IOException {
        String service = read("src/main/java/com/microservice/todo/service/TodoService.java");
        String kafka = read("src/main/java/com/microservice/todo/service/TodoEventPublisher.java");
        String inbox = read("src/main/java/com/microservice/todo/service/KafkaInboxConsumer.java");
        String s3 = read("src/main/java/com/microservice/todo/service/S3AuditService.java");
        String redis = read("src/main/java/com/microservice/todo/service/TodoCacheService.java");
        String mongo = read("src/main/java/com/microservice/todo/service/MongoLogService.java");
        for (String eventType : List.of("todo.created", "todo.updated", "todo.status_changed", "todo.completed", "todo.archived", "todo.restored", "todo.deleted", "todo.hard_deleted", "todo.audit.s3_written", "todo.audit.s3_failed")) {
            assertTrue(service.contains(eventType), eventType);
        }
        for (String header : List.of("event_id", "event_type", "service", "tenant", "trace_id", "correlation_id")) assertTrue(kafka.contains(header));
        assertTrue(inbox.contains("access.grant.created"));
        assertTrue(inbox.contains("access.grant.revoked"));
        assertTrue(s3.contains("/tenant/%s/users/%s/events/%s/%s_%s_%s.json"));
        assertTrue(s3.contains("SecretRedactor.redactMap"));
        for (String token : List.of("record:", "list:", "today:", "overdue:", "history:")) assertTrue(redis.contains(token));
        assertTrue(mongo.contains("SecretRedactor.redactMap"));
    }

    private String read(String file) throws IOException {
        return Files.readString(ROOT.resolve(file));
    }

    private List<String> keys(String file) throws IOException {
        return Files.readAllLines(ROOT.resolve(file)).stream()
                .filter(line -> !line.isBlank() && !line.startsWith("#") && line.contains("="))
                .map(line -> line.substring(0, line.indexOf('=')))
                .toList();
    }
}
