package com.microservice.todo.service;

import com.microservice.todo.dto.TodoEvent;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CompletableFuture;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Service;

@Service
public class TodoEventPublisher {
    private static final Logger log = LoggerFactory.getLogger(TodoEventPublisher.class);
    private final KafkaTemplate<String, TodoEvent> kafkaTemplate;

    public TodoEventPublisher(KafkaTemplate<String, TodoEvent> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    public CompletableFuture<SendResult<String, TodoEvent>> publishAsync(String topic, TodoEvent event) {
        try {
            ProducerRecord<String, TodoEvent> record = new ProducerRecord<>(topic, kafkaKey(event), event);
            header(record, "event_id", event.eventId());
            header(record, "event_type", event.eventType());
            header(record, "service", event.service());
            header(record, "tenant", event.tenant());
            header(record, "trace_id", event.traceId());
            header(record, "correlation_id", event.correlationId());
            return kafkaTemplate.send(record)
                    .whenComplete((result, ex) -> {
                        if (ex != null) {
                            log.warn("event=kafka.publish.failed event_id={} event_type={} detail={}", event.eventId(), event.eventType(), ex.getMessage());
                        } else {
                            log.debug("event=kafka.publish.sent event_id={} event_type={}", event.eventId(), event.eventType());
                        }
                    });
        } catch (Exception ex) {
            CompletableFuture<SendResult<String, TodoEvent>> failed = new CompletableFuture<>();
            failed.completeExceptionally(ex);
            return failed;
        }
    }

    private String kafkaKey(TodoEvent event) {
        if (event.tenant() != null && event.userId() != null && !event.userId().isBlank()) {
            return event.tenant() + ":" + event.userId();
        }
        return (event.tenant() == null ? "unknown" : event.tenant()) + ":" + (event.aggregateId() == null ? event.eventId() : event.aggregateId());
    }

    private void header(ProducerRecord<String, TodoEvent> record, String name, String value) {
        if (value != null) record.headers().add(name, value.getBytes(StandardCharsets.UTF_8));
    }
}
