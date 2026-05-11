package com.microapp.calculator.persistence;

import java.util.UUID;

public record OutboxEventRow(
        UUID id,
        String eventId,
        String tenant,
        String aggregateType,
        String aggregateId,
        String eventType,
        String topic,
        String payload
) {
}
