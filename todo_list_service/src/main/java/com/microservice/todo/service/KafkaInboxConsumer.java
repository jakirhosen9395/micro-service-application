package com.microservice.todo.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.microservice.todo.config.TodoProperties;
import com.microservice.todo.entity.InboxStatus;
import com.microservice.todo.entity.KafkaInboxEvent;
import com.microservice.todo.repository.AccessGrantRepository;
import com.microservice.todo.repository.KafkaInboxEventRepository;
import java.time.Instant;
import java.util.Map;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

@Service
public class KafkaInboxConsumer {
    private static final Logger log = LoggerFactory.getLogger(KafkaInboxConsumer.class);
    private final KafkaInboxEventRepository repository;
    private final AccessGrantRepository accessGrantRepository;
    private final ObjectMapper objectMapper;
    private final TodoProperties properties;

    public KafkaInboxConsumer(
            KafkaInboxEventRepository repository,
            AccessGrantRepository accessGrantRepository,
            ObjectMapper objectMapper,
            TodoProperties properties) {
        this.repository = repository;
        this.accessGrantRepository = accessGrantRepository;
        this.objectMapper = objectMapper;
        this.properties = properties;
    }

    @KafkaListener(topics = "#{'${todo.kafka.consume-topics}'.split(',')}", groupId = "${todo.kafka.consumer-group}")
    public void consume(ConsumerRecord<String, String> record) {
        String eventId = null;
        try {
            Map<String, Object> envelope = parsePayload(record.value());
            eventId = stringValue(envelope.getOrDefault("event_id", header(record, "event_id")));
            if (eventId == null || eventId.isBlank()) eventId = record.topic() + ":" + record.partition() + ":" + record.offset();
            if (repository.existsByEventId(eventId) || repository.findByTopicAndPartitionAndOffsetValue(record.topic(), record.partition(), record.offset()).isPresent()) {
                return;
            }
            String eventType = stringValue(envelope.getOrDefault("event_type", "unknown"));
            String sourceService = stringValue(envelope.get("service"));
            KafkaInboxEvent inbox = new KafkaInboxEvent();
            inbox.setEventId(eventId);
            inbox.setTenant(stringValue(envelope.get("tenant")));
            inbox.setTopic(record.topic());
            inbox.setPartition(record.partition());
            inbox.setOffsetValue(record.offset());
            inbox.setEventType(eventType);
            inbox.setSourceService(sourceService);
            inbox.setPayload(envelope);
            inbox.setStatus(InboxStatus.RECEIVED);
            try {
                repository.saveAndFlush(inbox);
            } catch (DataIntegrityViolationException duplicate) {
                log.debug("event=kafka.inbox.duplicate_ignored topic={} partition={} offset={} event_id={}", record.topic(), record.partition(), record.offset(), eventId);
                return;
            }

            if (sameService(sourceService)) {
                inbox.setStatus(InboxStatus.IGNORED);
                inbox.setProcessedAt(Instant.now());
                repository.save(inbox);
                return;
            }

            handleProjection(eventId, eventType, stringValue(envelope.get("tenant")), envelope.get("payload"));
            inbox.setStatus(InboxStatus.PROCESSED);
            inbox.setProcessedAt(Instant.now());
            repository.save(inbox);
        } catch (Exception ex) {
            log.warn("event=kafka.inbox.consume.failed topic={} partition={} offset={} detail={}", record.topic(), record.partition(), record.offset(), ex.getMessage());
            saveFailed(record, eventId, ex.getMessage());
        }
    }

    private void handleProjection(String eventId, String eventType, String tenant, Object payloadValue) {
        JsonNode payload = objectMapper.valueToTree(payloadValue == null ? Map.of() : payloadValue);
        if (eventType == null) return;
        if (eventType.equals("access.request.approved") || eventType.equals("access.grant.created") || eventType.equals("access.grant.approved") || eventType.equals("access.grant.active")) {
            upsertGrant(eventId, tenant, payload);
        } else if (eventType.equals("access.grant.revoked") || eventType.equals("access.request.rejected") || eventType.equals("access.grant.expired")) {
            String grantId = firstText(payload, "grant_id", "grantId", "id");
            if (grantId != null) accessGrantRepository.revokeGrant(grantId, eventId);
        }
    }

    private void upsertGrant(String eventId, String tenant, JsonNode payload) {
        String grantId = firstText(payload, "grant_id", "grantId", "id");
        String targetUserId = firstText(payload, "target_user_id", "targetUserId", "user_id", "userId");
        String granteeUserId = firstText(payload, "grantee_user_id", "granteeUserId", "requester_user_id", "requesterUserId", "actor_id", "actorId");
        String scope = firstText(payload, "scope");
        String status = firstText(payload, "status");
        Instant expiresAt = parseInstant(firstText(payload, "expires_at", "expiresAt"));
        if (grantId == null || targetUserId == null || granteeUserId == null || scope == null) return;
        accessGrantRepository.upsertGrant(grantId, tenant == null ? properties.getTenant() : tenant, targetUserId, granteeUserId, scope, status == null ? "ACTIVE" : status, expiresAt, eventId);
    }

    private Map<String, Object> parsePayload(String raw) throws Exception {
        if (raw == null || raw.isBlank()) return Map.of();
        return objectMapper.readValue(raw, new TypeReference<>() {});
    }

    private void saveFailed(ConsumerRecord<String, String> record, String eventId, String error) {
        try {
            String id = eventId == null || eventId.isBlank() ? record.topic() + ":" + record.partition() + ":" + record.offset() : eventId;
            if (repository.existsByEventId(id)) return;
            KafkaInboxEvent event = new KafkaInboxEvent();
            event.setEventId(id);
            event.setTopic(record.topic());
            event.setPartition(record.partition());
            event.setOffsetValue(record.offset());
            event.setEventType("unknown");
            event.setSourceService("unknown");
            event.setStatus(InboxStatus.FAILED);
            event.setErrorMessage(error);
            repository.save(event);
        } catch (Exception ignored) {
            // Do not throw from a failed failure-record write.
        }
    }

    private static Instant parseInstant(String value) {
        if (value == null || value.isBlank()) return null;
        try { return Instant.parse(value); } catch (Exception ex) { return null; }
    }

    private static String firstText(JsonNode node, String... names) {
        for (String name : names) {
            String value = text(node, name);
            if (value != null && !value.isBlank()) return value;
        }
        return null;
    }

    private static String text(JsonNode node, String field) {
        if (node == null || node.isMissingNode() || node.isNull()) return null;
        JsonNode value = node.get(field);
        return value == null || value.isNull() ? null : value.asText();
    }

    private boolean sameService(String sourceService) {
        if (sourceService == null || sourceService.isBlank()) return false;
        String own = normalizeServiceName(properties.getServiceName());
        String source = normalizeServiceName(sourceService);
        return own.equals(source);
    }

    private String normalizeServiceName(String value) {
        return value == null ? "" : value.trim().replace('-', '_');
    }

    private String header(ConsumerRecord<String, String> record, String key) {
        var header = record.headers().lastHeader(key);
        return header == null ? null : new String(header.value());
    }

    private String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}
