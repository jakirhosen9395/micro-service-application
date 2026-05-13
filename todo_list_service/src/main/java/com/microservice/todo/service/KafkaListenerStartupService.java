package com.microservice.todo.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.kafka.config.KafkaListenerEndpointRegistry;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class KafkaListenerStartupService {
    private static final Logger log = LoggerFactory.getLogger(KafkaListenerStartupService.class);
    private final KafkaListenerEndpointRegistry registry;
    private final DatabaseSchemaGuard schemaGuard;

    public KafkaListenerStartupService(KafkaListenerEndpointRegistry registry, DatabaseSchemaGuard schemaGuard) {
        this.registry = registry;
        this.schemaGuard = schemaGuard;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void startAfterApplicationReady() {
        startIfSchemaReady();
    }

    @Scheduled(initialDelay = 10000, fixedDelay = 10000)
    public void retryStartIfNeeded() {
        startIfSchemaReady();
    }

    private void startIfSchemaReady() {
        if (registry.getListenerContainers().stream().allMatch(container -> container.isRunning())) {
            return;
        }
        if (!schemaGuard.verifyAndLog()) {
            log.warn("event=kafka.listener.start status=deferred reason=database_schema_not_ready");
            return;
        }
        registry.getListenerContainers().forEach(container -> {
            if (!container.isRunning()) {
                container.start();
            }
        });
        log.info("event=kafka.listener.start status=started containers={}", registry.getListenerContainers().size());
    }
}
