package com.microapp.calculator;

import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertTrue;

class HealthContractTest {
    @Test
    void healthDependencyKeysAreExactAndCanonical() throws Exception {
        String source = Files.readString(Path.of("src/main/java/com/microapp/calculator/health/HealthService.java"));
        for (String key : List.of("jwt", "postgres", "redis", "kafka", "s3", "mongodb", "apm", "elasticsearch")) {
            assertTrue(source.contains("dependencies.put(\"" + key + "\""), "missing dependency " + key);
        }
        assertTrue(source.contains("POSTGRES_UNAVAILABLE"));
        assertTrue(source.contains("REDIS_UNAVAILABLE"));
        assertTrue(source.contains("KAFKA_UNAVAILABLE"));
        assertTrue(source.contains("S3_UNAVAILABLE"));
        assertTrue(source.contains("MONGODB_UNAVAILABLE"));
        assertTrue(source.contains("APM_UNAVAILABLE"));
        assertTrue(source.contains("ELASTICSEARCH_UNAVAILABLE"));
    }
}
