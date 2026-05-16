package com.microapp.calculator.kafka;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.logging.MongoStructuredLogger;
import com.microapp.calculator.persistence.OutboxEventRow;
import com.microapp.calculator.persistence.OutboxRepository;
import com.microapp.calculator.util.SecretRedactor;
import co.elastic.apm.api.CaptureTransaction;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.header.internals.RecordHeader;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.sql.SQLException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

@Component
public class OutboxPublisher {

    private static final Logger log = LoggerFactory.getLogger(OutboxPublisher.class);

    private static final int OUTBOX_CLAIM_LIMIT = 25;
    private static final long CLAIM_STACK_TRACE_LOG_INTERVAL_MS = 60_000L;

    private final OutboxRepository repository;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final AppProperties props;
    private final ObjectMapper mapper;
    private final MongoStructuredLogger mongoLogger;
    private final AtomicLong lastClaimStackTraceLogAtMillis = new AtomicLong(0L);

    public OutboxPublisher(
            OutboxRepository repository,
            KafkaTemplate<String, String> kafkaTemplate,
            AppProperties props,
            ObjectMapper mapper,
            MongoStructuredLogger mongoLogger
    ) {
        this.repository = repository;
        this.kafkaTemplate = kafkaTemplate;
        this.props = props;
        this.mapper = mapper;
        this.mongoLogger = mongoLogger;
    }

    @Scheduled(fixedDelay = 3000, initialDelay = 5000)
    @CaptureTransaction(value = "calculator.outbox.publish_pending", type = "messaging")
    public void publishPending() {
        final List<OutboxEventRow> rows;

        try {
            rows = repository.claimPending(OUTBOX_CLAIM_LIMIT);
        } catch (Exception ex) {
            handleClaimFailure(ex);
            return;
        }

        for (OutboxEventRow row : rows) {
            publish(row);
        }
    }

    private void publish(OutboxEventRow row) {
        try {
            String key = kafkaKey(row.payload(), row.tenant(), row.aggregateId());

            ProducerRecord<String, String> record = new ProducerRecord<>(
                    row.topic(),
                    key,
                    row.payload()
            );

            addHeader(record, "event_id", row.eventId());
            addHeader(record, "event_type", row.eventType());
            addHeader(record, "service", props.getServiceName());
            addHeader(record, "tenant", row.tenant());

            JsonNode root = mapper.readTree(row.payload());
            addHeader(record, "trace_id", text(root, "trace_id"));
            addHeader(record, "correlation_id", text(root, "correlation_id"));

            kafkaTemplate.send(record).get(10, TimeUnit.SECONDS);
            repository.markSent(row.id());
        } catch (Exception ex) {
            String message = safeMessage(ex);

            log.warn(
                    "event=kafka.outbox.publish.failed event_id={} event_type={} topic={} aggregate_id={} message={}",
                    row.eventId(),
                    row.eventType(),
                    row.topic(),
                    row.aggregateId(),
                    message
            );

            safeMongoWarn(
                    "kafka.outbox.publish.failed",
                    "outbox publish failed",
                    "KAFKA_PUBLISH_FAILED",
                    Map.of(
                            "event_id", row.eventId(),
                            "event_type", row.eventType(),
                            "topic", row.topic(),
                            "aggregate_id", row.aggregateId(),
                            "message", message
                    )
            );

            tryDeadLetter(row, message);
        }
    }

    private void tryDeadLetter(OutboxEventRow row, String message) {
        try {
            ProducerRecord<String, String> dlq = new ProducerRecord<>(
                    props.getKafka().getDeadLetterTopic(),
                    row.tenant() + ":" + row.aggregateId(),
                    row.payload()
            );

            addHeader(dlq, "event_id", row.eventId());
            addHeader(dlq, "event_type", row.eventType());
            addHeader(dlq, "service", props.getServiceName());
            addHeader(dlq, "tenant", row.tenant());
            addHeader(dlq, "dead_letter_reason", message);

            kafkaTemplate.send(dlq).get(5, TimeUnit.SECONDS);
            repository.markDeadLettered(row.id(), message);
        } catch (Exception dlqFailure) {
            String dlqMessage = safeMessage(dlqFailure);

            log.warn(
                    "event=kafka.outbox.dead_letter.failed event_id={} event_type={} message={}",
                    row.eventId(),
                    row.eventType(),
                    dlqMessage
            );

            repository.markRetry(row.id(), message);
        }
    }

    private void handleClaimFailure(Exception ex) {
        Throwable root = rootCause(ex);
        SQLException sqlException = findSqlException(ex);

        String message = safeMessage(ex);
        String rootMessage = safeMessage(root);

        Map<String, Object> metadata = new LinkedHashMap<>();
        metadata.put("message", message);
        metadata.put("root_exception", root.getClass().getName());
        metadata.put("root_message", rootMessage);

        if (sqlException != null) {
            metadata.put("sql_state", safe(sqlException.getSQLState()));
            metadata.put("vendor_code", sqlException.getErrorCode());
        }

        if (shouldLogClaimStackTrace()) {
            log.error(
                    "event=kafka.outbox.claim.failed root_exception={} sql_state={} vendor_code={} message={} root_message={}",
                    root.getClass().getName(),
                    sqlException == null ? "" : safe(sqlException.getSQLState()),
                    sqlException == null ? "" : sqlException.getErrorCode(),
                    message,
                    rootMessage,
                    ex
            );
        } else {
            log.error(
                    "event=kafka.outbox.claim.failed root_exception={} sql_state={} vendor_code={} message={} root_message={}",
                    root.getClass().getName(),
                    sqlException == null ? "" : safe(sqlException.getSQLState()),
                    sqlException == null ? "" : sqlException.getErrorCode(),
                    message,
                    rootMessage
            );
        }

        safeMongoError(
                "kafka.outbox.claim.failed",
                "outbox claim failed",
                "OUTBOX_CLAIM_FAILED",
                ex,
                metadata
        );
    }

    private boolean shouldLogClaimStackTrace() {
        long now = System.currentTimeMillis();
        long previous = lastClaimStackTraceLogAtMillis.get();

        if (now - previous < CLAIM_STACK_TRACE_LOG_INTERVAL_MS) {
            return false;
        }

        return lastClaimStackTraceLogAtMillis.compareAndSet(previous, now);
    }

    private String kafkaKey(String payload, String tenant, String aggregateId) throws Exception {
        JsonNode root = mapper.readTree(payload);
        String userId = text(root, "user_id");

        if (userId != null && !userId.isBlank()) {
            return tenant + ":" + userId;
        }

        return tenant + ":" + aggregateId;
    }

    private void safeMongoError(
            String eventName,
            String message,
            String errorCode,
            Exception ex,
            Map<String, Object> metadata
    ) {
        try {
            mongoLogger.error(eventName, message, errorCode, ex, metadata);
        } catch (Throwable mongoFailure) {
            log.warn(
                    "event=mongodb.structured_log.failed source_event={} exception={} message={}",
                    eventName,
                    mongoFailure.getClass().getName(),
                    safeMessage(mongoFailure)
            );
        }
    }

    private void safeMongoWarn(
            String eventName,
            String message,
            String errorCode,
            Map<String, Object> metadata
    ) {
        try {
            mongoLogger.warn(eventName, message, errorCode, metadata);
        } catch (Throwable mongoFailure) {
            log.warn(
                    "event=mongodb.structured_log.failed source_event={} exception={} message={}",
                    eventName,
                    mongoFailure.getClass().getName(),
                    safeMessage(mongoFailure)
            );
        }
    }

    private static void addHeader(ProducerRecord<String, String> record, String key, String value) {
        if (value != null) {
            record.headers().add(new RecordHeader(key, value.getBytes(StandardCharsets.UTF_8)));
        }
    }

    private static String text(JsonNode node, String snakeCaseField) {
        if (node == null) {
            return null;
        }

        JsonNode snake = node.get(snakeCaseField);
        if (snake != null && !snake.isNull()) {
            return snake.asText();
        }

        String camel = toCamel(snakeCaseField);
        JsonNode camelNode = node.get(camel);

        return camelNode == null || camelNode.isNull() ? null : camelNode.asText();
    }

    private static String toCamel(String value) {
        StringBuilder sb = new StringBuilder();
        boolean upper = false;

        for (char ch : value.toCharArray()) {
            if (ch == '_') {
                upper = true;
            } else if (upper) {
                sb.append(Character.toUpperCase(ch));
                upper = false;
            } else {
                sb.append(ch);
            }
        }

        return sb.toString();
    }

    private static Throwable rootCause(Throwable throwable) {
        Throwable current = throwable;

        while (current.getCause() != null && current.getCause() != current) {
            current = current.getCause();
        }

        return current;
    }

    private static SQLException findSqlException(Throwable throwable) {
        Throwable current = throwable;

        while (current != null) {
            if (current instanceof SQLException sqlException) {
                return sqlException;
            }

            current = current.getCause();
        }

        return null;
    }

    private static String safeMessage(Throwable throwable) {
        if (throwable == null) {
            return "";
        }

        String message = throwable.getMessage();
        if (message == null || message.isBlank()) {
            message = throwable.getClass().getName();
        }

        return SecretRedactor.redact(message);
    }

    private static String safe(String value) {
        return value == null ? "" : SecretRedactor.redact(value);
    }
}
