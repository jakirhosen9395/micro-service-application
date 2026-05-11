package com.microapp.calculator.kafka;

import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.persistence.OutboxRepository;
import org.springframework.stereotype.Service;

@Service
public class OutboxService {
    private final AppProperties props;
    private final OutboxRepository repository;

    public OutboxService(AppProperties props, OutboxRepository repository) {
        this.props = props;
        this.repository = repository;
    }

    public void enqueue(EventEnvelope envelope) {
        repository.insert(
                envelope.eventId(),
                envelope.tenant(),
                envelope.aggregateType(),
                envelope.aggregateId(),
                envelope.eventType(),
                envelope.eventVersion(),
                props.getKafka().getEventsTopic(),
                envelope,
                envelope.requestId(),
                envelope.traceId(),
                envelope.correlationId()
        );
    }

    public void enqueueToTopic(EventEnvelope envelope, String topic) {
        repository.insert(
                envelope.eventId(),
                envelope.tenant(),
                envelope.aggregateType(),
                envelope.aggregateId(),
                envelope.eventType(),
                envelope.eventVersion(),
                topic,
                envelope,
                envelope.requestId(),
                envelope.traceId(),
                envelope.correlationId()
        );
    }
}
