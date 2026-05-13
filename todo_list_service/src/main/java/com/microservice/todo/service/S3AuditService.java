package com.microservice.todo.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.microservice.todo.config.TodoProperties;
import com.microservice.todo.dto.TodoEvent;
import com.microservice.todo.dto.TodoResponse;
import com.microservice.todo.security.UserPrincipal;
import com.microservice.todo.util.RequestContext;
import com.microservice.todo.util.SecretRedactor;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

@Service
public class S3AuditService {
    private static final Logger log = LoggerFactory.getLogger(S3AuditService.class);
    private static final DateTimeFormatter PATH_DATE = DateTimeFormatter.ofPattern("yyyy/MM/dd").withZone(ZoneOffset.UTC);
    private static final DateTimeFormatter FILE_TS = DateTimeFormatter.ofPattern("HHmmss").withZone(ZoneOffset.UTC);

    private final S3Client s3Client;
    private final ObjectMapper objectMapper;
    private final TodoProperties properties;

    public S3AuditService(S3Client s3Client, ObjectMapper objectMapper, TodoProperties properties) {
        this.s3Client = s3Client;
        this.objectMapper = objectMapper;
        this.properties = properties;
    }

    public S3AuditResult writeSnapshot(TodoEvent event, TodoResponse response) {
        try {
            Instant now = Instant.now();
            String eventKey = eventKey(event, now);
            byte[] payload = objectMapper.writerWithDefaultPrettyPrinter()
                    .writeValueAsString(snapshot(event, response, now))
                    .getBytes(StandardCharsets.UTF_8);
            put(eventKey, payload);
            return S3AuditResult.written(eventKey);
        } catch (Exception ex) {
            log.warn("event=s3.audit.failed event_type={} event_id={} detail={}", event.eventType(), event.eventId(), ex.getMessage());
            return S3AuditResult.failed("S3_AUDIT_WRITE_FAILED");
        }
    }

    public S3AuditResult writeActivitySnapshot(TodoEvent event, UserPrincipal user, String aggregateId, Map<String, Object> payload) {
        try {
            Instant now = Instant.now();
            String eventKey = eventKey(event, now);
            byte[] body = objectMapper.writerWithDefaultPrettyPrinter()
                    .writeValueAsString(activitySnapshot(event, user, aggregateId, payload, now))
                    .getBytes(StandardCharsets.UTF_8);
            put(eventKey, body);
            return S3AuditResult.written(eventKey);
        } catch (Exception ex) {
            log.warn("event=s3.audit.failed event_type={} event_id={} detail={}", event.eventType(), event.eventId(), ex.getMessage());
            return S3AuditResult.failed("S3_AUDIT_WRITE_FAILED");
        }
    }

    private String eventKey(TodoEvent event, Instant now) {
        String prefix = trimSlashes(properties.getS3().getAuditPrefix());
        String actor = safeSegment(event.actorId() == null ? "unknown" : event.actorId());
        return "%s/tenant/%s/users/%s/events/%s/%s_%s_%s.json".formatted(
                prefix,
                safeSegment(event.tenant()),
                actor,
                PATH_DATE.format(now),
                FILE_TS.format(now),
                event.eventType().replace('.', '_'),
                event.eventId());
    }

    private Map<String, Object> snapshot(TodoEvent event, TodoResponse response, Instant now) {
        var metadata = RequestContext.metadata();
        Map<String, Object> data = canonicalAuditEnvelope(event, now);
        data.put("target_user_id", null);
        data.put("client_ip", metadata.clientIp());
        data.put("user_agent", metadata.userAgent());
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("todo_id", response.id());
        payload.put("title", response.title());
        payload.put("description", response.description());
        payload.put("status", response.status());
        payload.put("priority", response.priority());
        payload.put("due_date", response.dueDate());
        payload.put("tags", response.tags());
        payload.put("created_at", response.createdAt());
        payload.put("updated_at", response.updatedAt());
        data.put("payload", SecretRedactor.redactMap(payload));
        return data;
    }

    private Map<String, Object> activitySnapshot(TodoEvent event, UserPrincipal user, String aggregateId, Map<String, Object> payload, Instant now) {
        var metadata = RequestContext.metadata();
        Map<String, Object> data = canonicalAuditEnvelope(event, now);
        data.put("target_user_id", null);
        data.put("client_ip", metadata.clientIp());
        data.put("user_agent", metadata.userAgent());
        data.put("payload", SecretRedactor.redactMap(payload == null ? Map.of() : payload));
        return data;
    }

    private Map<String, Object> canonicalAuditEnvelope(TodoEvent event, Instant now) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("event_id", event.eventId());
        data.put("event_type", event.eventType());
        data.put("service", properties.getServiceName());
        data.put("environment", displayEnvironment(properties.getEnv()));
        data.put("tenant", event.tenant());
        data.put("user_id", event.userId());
        data.put("actor_id", event.actorId());
        data.put("aggregate_type", event.aggregateType());
        data.put("aggregate_id", event.aggregateId());
        data.put("request_id", event.requestId());
        data.put("trace_id", event.traceId());
        data.put("correlation_id", event.correlationId());
        data.put("timestamp", now);
        return data;
    }

    private void put(String key, byte[] payload) {
        s3Client.putObject(PutObjectRequest.builder()
                        .bucket(properties.getS3().getBucket())
                        .key(key)
                        .contentType("application/json")
                        .build(),
                RequestBody.fromBytes(payload));
    }

    private String trimSlashes(String value) {
        if (value == null || value.isBlank()) return properties.getServiceName() + "/" + displayEnvironment(properties.getEnv());
        return value.replaceAll("^/+|/+$", "");
    }

    private String safeSegment(String value) {
        if (value == null || value.isBlank()) return "unknown";
        return value.replaceAll("[^A-Za-z0-9._=-]", "_");
    }

    private String displayEnvironment(String env) {
        return switch (env == null ? "" : env.toLowerCase()) {
            case "dev", "development" -> "development";
            case "stage", "staging" -> "stage";
            case "prod", "production" -> "production";
            default -> env;
        };
    }
}
