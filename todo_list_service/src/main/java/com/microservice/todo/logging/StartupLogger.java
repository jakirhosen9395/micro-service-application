package com.microservice.todo.logging;

import com.microservice.todo.config.TodoProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

@Component
public class StartupLogger {
    private static final Logger log = LoggerFactory.getLogger(StartupLogger.class);
    private final TodoProperties properties;
    private final Environment environment;

    public StartupLogger(TodoProperties properties, Environment environment) {
        this.properties = properties;
        this.environment = environment;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void onReady() {
        String port = environment.getProperty("server.port", "8080");
        String host = environment.getProperty("server.address", "0.0.0.0");
        log.info("event=application.started message=application started service={} version={} environment={} host={} port={} docs=/docs",
                properties.getServiceName(), properties.getServiceVersion(), properties.getEnv(), host, port);
    }
}
