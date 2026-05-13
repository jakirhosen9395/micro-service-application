package com.microservice.todo.config;

import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

@Component
public class ApmConfig {
    private static final Logger log = LoggerFactory.getLogger(ApmConfig.class);
    private final TodoProperties properties;

    public ApmConfig(TodoProperties properties) {
        this.properties = properties;
    }

    @PostConstruct
    public void attachApmAgent() {
        var apm = properties.getApm();
        if (apm.getServerUrl() == null || apm.getServerUrl().isBlank()) {
            log.warn("event=apm.config.missing message=APM server URL missing");
            return;
        }

        try {
            ElasticApmBootstrap.attach(properties);
            log.info("event=apm.started status=enabled service={}", properties.getServiceName());
        } catch (Exception ex) {
            log.warn("event=apm.unavailable detail={}", ex.getMessage());
        }
    }
}
