package com.microservice.todo.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.microservice.todo.config.TodoProperties;
import com.microservice.todo.dto.TodoEvent;
import com.microservice.todo.entity.OutboxStatus;
import com.microservice.todo.repository.OutboxEventRepository;
import co.elastic.apm.api.CaptureTransaction;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.TimeUnit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class OutboxRetryService {
    private static final Logger log = LoggerFactory.getLogger(OutboxRetryService.class);
    private static final int MAX_ATTEMPTS = 5;

    private final OutboxEventRepository repository;
    private final TodoEventPublisher publisher;
    private final ObjectMapper objectMapper;
    private final TodoProperties properties;
    private final DatabaseSchemaGuard schemaGuard;

    public OutboxRetryService(OutboxEventRepository repository, TodoEventPublisher publisher, ObjectMapper objectMapper, TodoProperties properties, DatabaseSchemaGuard schemaGuard) {
        this.repository = repository;
        this.publisher = publisher;
        this.objectMapper = objectMapper;
        this.properties = properties;
        this.schemaGuard = schemaGuard;
    }

    @Scheduled(fixedDelayString = "${TODO_OUTBOX_RETRY_DELAY_MS:30000}")
    @Transactional
    @CaptureTransaction(value = "todo.outbox.retry_pending", type = "messaging")
    public void retryPendingEvents() {
        if (!schemaGuard.isReady()) {
            log.warn("event=outbox.publish.retry status=deferred reason=database_schema_not_ready");
            return;
        }
        var events = repository.findReady(List.of(OutboxStatus.PENDING, OutboxStatus.FAILED), Instant.now(), PageRequest.of(0, 25));
        for (var outbox : events) {
            try {
                outbox.setStatus(OutboxStatus.PROCESSING);
                repository.saveAndFlush(outbox);

                TodoEvent event = objectMapper.convertValue(outbox.getPayload(), TodoEvent.class);
                publisher.publishAsync(outbox.getTopic(), event).get(10, TimeUnit.SECONDS);

                outbox.setStatus(OutboxStatus.SENT);
                outbox.setLastError(null);
                outbox.setNextRetryAt(null);
                outbox.setSentAt(Instant.now());
                repository.save(outbox);
            } catch (Exception ex) {
                outbox.setAttemptCount(outbox.getAttemptCount() + 1);
                boolean deadLetter = outbox.getAttemptCount() >= MAX_ATTEMPTS;
                if (deadLetter) publishDeadLetter(outbox);
                outbox.setStatus(deadLetter ? OutboxStatus.DEAD_LETTERED : OutboxStatus.FAILED);
                outbox.setLastError(rootMessage(ex));
                outbox.setNextRetryAt(Instant.now().plus(Duration.ofMillis(Math.min(300000, properties.getOutbox().getRetryDelayMs() * Math.max(1, outbox.getAttemptCount())))));
                repository.save(outbox);
                log.warn("event=outbox.publish.retry status=failed id={} attempts={} detail={}", outbox.getId(), outbox.getAttemptCount(), rootMessage(ex));
            }
        }
    }

    private void publishDeadLetter(com.microservice.todo.entity.OutboxEvent outbox) {
        try {
            TodoEvent event = objectMapper.convertValue(outbox.getPayload(), TodoEvent.class);
            publisher.publishAsync(properties.getKafka().getDeadLetterTopic(), event).get(10, TimeUnit.SECONDS);
        } catch (Exception dlqEx) {
            log.warn("event=outbox.dead_letter_publish_failed detail={}", rootMessage(dlqEx));
        }
    }

    private String rootMessage(Exception ex) {
        Throwable cause = ex.getCause();
        return cause == null ? ex.getMessage() : cause.getMessage();
    }
}
