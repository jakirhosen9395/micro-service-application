package com.microapp.calculator.s3;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.kafka.EventEnvelope;
import com.microapp.calculator.util.RequestContext;
import com.microapp.calculator.util.SecretRedactor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;

@Service
public class S3AuditService {
    private static final Logger log = LoggerFactory.getLogger(S3AuditService.class);
    private static final DateTimeFormatter YYYY = DateTimeFormatter.ofPattern("yyyy").withZone(ZoneOffset.UTC);
    private static final DateTimeFormatter MM = DateTimeFormatter.ofPattern("MM").withZone(ZoneOffset.UTC);
    private static final DateTimeFormatter DD = DateTimeFormatter.ofPattern("dd").withZone(ZoneOffset.UTC);
    private static final DateTimeFormatter HHMMSS = DateTimeFormatter.ofPattern("HHmmss").withZone(ZoneOffset.UTC);

    private final S3Client s3Client;
    private final AppProperties props;
    private final ObjectMapper mapper;

    public S3AuditService(S3Client s3Client, AppProperties props, ObjectMapper mapper) {
        this.s3Client = s3Client;
        this.props = props;
        this.mapper = mapper;
    }

    public String writeAuditSnapshot(EventEnvelope envelope, String targetUserId) {
        try {
            Instant now = Instant.now();
            String key = auditKey(envelope, now);
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("event_id", envelope.eventId());
            body.put("event_type", envelope.eventType());
            body.put("service", props.getServiceName());
            body.put("environment", props.getEnvironment());
            body.put("tenant", envelope.tenant());
            body.put("user_id", envelope.userId());
            body.put("actor_id", envelope.actorId());
            body.put("target_user_id", targetUserId);
            body.put("aggregate_type", envelope.aggregateType());
            body.put("aggregate_id", envelope.aggregateId());
            body.put("request_id", envelope.requestId());
            body.put("trace_id", envelope.traceId());
            body.put("correlation_id", envelope.correlationId());
            body.put("client_ip", RequestContext.clientIp());
            body.put("user_agent", RequestContext.userAgent());
            body.put("timestamp", now.toString());
            body.put("payload", SecretRedactor.sanitize(envelope.payload()));
            byte[] bytes = mapper.writerWithDefaultPrettyPrinter().writeValueAsBytes(body);
            PutObjectRequest request = PutObjectRequest.builder()
                    .bucket(props.getS3().getBucket())
                    .key(key)
                    .contentType("application/json")
                    .contentLength((long) bytes.length)
                    .build();
            s3Client.putObject(request, RequestBody.fromBytes(bytes));
            return key;
        } catch (Exception ex) {
            log.warn("event=s3.audit.write.failed event_id={} message={}", envelope.eventId(), SecretRedactor.redact(ex.getMessage()));
            return null;
        }
    }

    public String auditKey(EventEnvelope envelope, Instant timestamp) {
        String actor = envelope.actorId() == null || envelope.actorId().isBlank() ? "unknown" : safePath(envelope.actorId());
        String slug = safePath(envelope.eventType().replace('.', '_'));
        return props.getServiceName() + "/" + props.getEnvironment()
                + "/tenant/" + safePath(envelope.tenant())
                + "/users/" + actor
                + "/events/" + YYYY.format(timestamp)
                + "/" + MM.format(timestamp)
                + "/" + DD.format(timestamp)
                + "/" + HHMMSS.format(timestamp) + "_" + slug + "_" + safePath(envelope.eventId()) + ".json";
    }

    private static String safePath(String value) {
        return value == null ? "null" : value.replaceAll("[^A-Za-z0-9._=-]", "_");
    }
}
