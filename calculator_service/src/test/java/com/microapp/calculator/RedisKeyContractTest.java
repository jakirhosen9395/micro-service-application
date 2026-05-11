package com.microapp.calculator;

import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertTrue;

class RedisKeyContractTest {
    @Test
    void redisKeysUseCanonicalEnvironmentServiceNamespaceAndTtl() throws Exception {
        String source = Files.readString(Path.of("src/main/java/com/microapp/calculator/redis/CalculationCache.java"));
        assertTrue(source.contains("props.getEnvironment() + \":\" + props.getServiceName() + \":\""));
        assertTrue(source.contains("record:"));
        assertTrue(source.contains("history:"));
        assertTrue(source.contains("Duration.ofSeconds(props.getRedisCacheTtlSeconds())"));
        assertTrue(source.contains("redis.delete(redis.keys(prefix + \"*\"))"));
    }
}
