package com.microapp.calculator;

import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.kafka.EventEnvelope;
import com.microapp.calculator.kafka.EventFactory;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class EventEnvelopeTest {
    @Test
    void createsCanonicalEventEnvelope() {
        AppProperties props = props();
        EventFactory factory = new EventFactory(props);
        EventEnvelope event = factory.create("calculation.completed", "user-1", "user-1", "calculation", "calc-1", Map.of("result", "30"));
        assertTrue(event.eventId().startsWith("evt-"));
        assertEquals("calculation.completed", event.eventType());
        assertEquals("1.0", event.eventVersion());
        assertEquals("calculator_service", event.service());
        assertEquals("development", event.environment());
        assertEquals("dev", event.tenant());
        assertEquals("user-1", event.userId());
        assertEquals("user-1", event.actorId());
        assertEquals("calculation", event.aggregateType());
        assertEquals("calc-1", event.aggregateId());
        assertNotNull(event.requestId());
        assertNotNull(event.traceId());
        assertNotNull(event.correlationId());
    }

    @Test
    void requiredCalculatorEventTypesAreRepresentable() {
        EventFactory factory = new EventFactory(props());
        for (String type : new String[]{"calculation.completed", "calculation.failed", "calculation.history.cleared", "calculation.audit.s3_written", "calculation.audit.s3_failed"}) {
            EventEnvelope event = factory.create(type, "user-1", "actor-1", "calculation", "calc-1", Map.of());
            assertEquals(type, event.eventType());
            assertEquals("calculator_service", event.service());
            assertEquals("1.0", event.eventVersion());
        }
    }

    private static AppProperties props() {
        AppProperties props = new AppProperties();
        props.setServiceName("calculator_service");
        props.setEnvironment("development");
        props.setTenant("dev");
        return props;
    }
}
