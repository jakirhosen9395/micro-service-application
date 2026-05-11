package com.microapp.calculator;

import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.kafka.EventEnvelope;
import com.microapp.calculator.s3.S3AuditService;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;

class S3AuditKeyFormatTest {
    @Test
    void usesCanonicalS3AuditKeyPattern() {
        AppProperties props = new AppProperties();
        props.setServiceName("calculator_service");
        props.setEnvironment("development");
        props.setTenant("dev");
        AppProperties.S3 s3 = new AppProperties.S3();
        s3.setBucket("microservice");
        props.setS3(s3);
        S3AuditService service = new S3AuditService(null, props, null);
        EventEnvelope envelope = new EventEnvelope("evt-1", "calculation.completed", "1.0", "calculator_service", "development", "dev", Instant.parse("2026-05-09T10:16:12Z"), "req-1", "trace-1", "corr-1", "user-1", "actor-1", "calculation", "calc-1", Map.of());
        assertEquals("calculator_service/development/tenant/dev/users/actor-1/events/2026/05/09/101612_calculation_completed_evt-1.json", service.auditKey(envelope, Instant.parse("2026-05-09T10:16:12Z")));
    }
}
