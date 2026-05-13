package com.microapp.calculator.kafka;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.persistence.AccessGrantRepository;
import com.microapp.calculator.persistence.InboxRepository;
import com.microapp.calculator.util.SecretRedactor;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.stereotype.Component;

import java.time.Instant;

@Component
public class KafkaInboxConsumer {
    private static final Logger log = LoggerFactory.getLogger(KafkaInboxConsumer.class);
    private final InboxRepository inboxRepository;
    private final AccessGrantRepository accessGrantRepository;
    private final ObjectMapper mapper;
    private final AppProperties props;

    public KafkaInboxConsumer(InboxRepository inboxRepository, AccessGrantRepository accessGrantRepository, ObjectMapper mapper, AppProperties props) {
        this.inboxRepository = inboxRepository;
        this.accessGrantRepository = accessGrantRepository;
        this.mapper = mapper;
        this.props = props;
    }

    @KafkaListener(topics = "#{@kafkaConsumeTopics}", groupId = "${calc.kafka.consumer-group}")
    public void consume(ConsumerRecord<String, String> record, Acknowledgment ack) {
        String eventId = null;
        try {
            JsonNode root = mapper.readTree(record.value());
            eventId = text(root, "event_id");
            String eventType = text(root, "event_type");
            String tenant = text(root, "tenant");
            String sourceService = text(root, "service");
            if (eventId == null || eventType == null) {
                ack.acknowledge();
                return;
            }
            boolean inserted = inboxRepository.insertReceived(eventId, tenant, record.topic(), record.partition(), record.offset(), eventType, sourceService, record.value());
            if (!inserted) {
                ack.acknowledge();
                return;
            }
            if (props.getServiceName().equals(sourceService)) {
                inboxRepository.markIgnored(eventId);
                ack.acknowledge();
                return;
            }
            handleEvent(eventId, eventType, tenant, root.path("payload"));
            inboxRepository.markProcessed(eventId);
            ack.acknowledge();
        } catch (Exception ex) {
            if (eventId != null) {
                inboxRepository.markFailed(eventId, SecretRedactor.redact(ex.getMessage()));
            }
            log.warn("event=kafka.inbox.consume.failed topic={} partition={} offset={} message={}", record.topic(), record.partition(), record.offset(), SecretRedactor.redact(ex.getMessage()));
            ack.acknowledge();
        }
    }

    private void handleEvent(String eventId, String eventType, String tenant, JsonNode payload) {
        if (eventType == null) {
            return;
        }
        if (eventType.equals("access.request.approved") || eventType.equals("access.grant.approved") || eventType.equals("access.grant.created") || eventType.equals("access.grant.active")) {
            upsertGrant(eventId, tenant, payload);
        } else if (eventType.equals("access.grant.revoked") || eventType.equals("access.request.rejected") || eventType.equals("access.grant.expired")) {
            String grantId = firstText(payload, "grant_id", "grantId", "id");
            if (grantId != null) {
                accessGrantRepository.revokeGrant(grantId, eventId);
            }
        }
    }

    private void upsertGrant(String eventId, String tenant, JsonNode payload) {
        String grantId = firstText(payload, "grant_id", "grantId", "id");
        String targetUserId = firstText(payload, "target_user_id", "targetUserId", "user_id", "userId");
        String granteeUserId = firstText(payload, "grantee_user_id", "granteeUserId", "requester_user_id", "requesterUserId", "actor_id", "actorId");
        String scope = firstText(payload, "scope");
        String status = firstText(payload, "status");
        Instant expiresAt = parseInstant(firstText(payload, "expires_at", "expiresAt"));
        if (grantId == null || targetUserId == null || granteeUserId == null || scope == null) {
            return;
        }
        accessGrantRepository.upsertGrant(grantId, tenant == null ? props.getTenant() : tenant, targetUserId, granteeUserId, scope, status == null ? "ACTIVE" : status, expiresAt, eventId);
    }

    private static Instant parseInstant(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            return Instant.parse(value);
        } catch (Exception ex) {
            return null;
        }
    }

    private static String firstText(JsonNode node, String... names) {
        for (String name : names) {
            String value = text(node, name);
            if (value != null && !value.isBlank()) {
                return value;
            }
        }
        return null;
    }

    private static String text(JsonNode node, String field) {
        if (node == null || node.isMissingNode() || node.isNull()) {
            return null;
        }
        JsonNode value = node.get(field);
        if (value != null && !value.isNull()) {
            return value.asText();
        }
        return null;
    }
}
