package com.microapp.calculator.health;

import com.microapp.calculator.logging.MongoStructuredLogger;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.util.Map;

@Component
@Order(2)
public class StartupDependencyVerifier implements ApplicationRunner {
    private final HealthService healthService;
    private final MongoStructuredLogger mongoLogger;

    public StartupDependencyVerifier(HealthService healthService, MongoStructuredLogger mongoLogger) {
        this.healthService = healthService;
        this.mongoLogger = mongoLogger;
    }

    @Override
    public void run(ApplicationArguments args) {
        mongoLogger.ensureIndexes();
        HealthResponse response = healthService.health();
        for (Map.Entry<String, DependencyResult> entry : response.dependencies().entrySet()) {
            if ("down".equals(entry.getValue().status()) && !entry.getKey().equals("apm") && !entry.getKey().equals("elasticsearch")) {
                throw new IllegalStateException("Required dependency is down at startup: " + entry.getKey() + " error=" + entry.getValue().errorCode());
            }
        }
        mongoLogger.info("application.started", "application started", Map.of("service", response.service(), "environment", response.environment(), "version", response.version()));
    }
}
