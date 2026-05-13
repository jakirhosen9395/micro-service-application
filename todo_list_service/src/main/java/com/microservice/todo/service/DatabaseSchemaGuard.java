package com.microservice.todo.service;

import com.microservice.todo.config.TodoProperties;
import jakarta.annotation.PostConstruct;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

@Component
public class DatabaseSchemaGuard {
    private static final Logger log = LoggerFactory.getLogger(DatabaseSchemaGuard.class);
    private final JdbcTemplate jdbcTemplate;
    private final TodoProperties properties;
    private volatile boolean ready;
    private volatile boolean repairAttempted;

    public DatabaseSchemaGuard(JdbcTemplate jdbcTemplate, TodoProperties properties) {
        this.jdbcTemplate = jdbcTemplate;
        this.properties = properties;
    }

    @PostConstruct
    public void initializeSchema() {
        if (!verifyAndLog()) {
            throw new IllegalStateException("todo postgres schema is not ready");
        }
    }

    public boolean isReady() {
        if (ready) return true;
        ensureRequiredTables(false);
        ready = checkRequiredTables(false);
        return ready;
    }

    public boolean verifyAndLog() {
        ensureRequiredTables(true);
        ready = checkRequiredTables(true);
        return ready;
    }

    private void ensureRequiredTables(boolean logResult) {
        if (repairAttempted) return;
        synchronized (this) {
            if (repairAttempted) return;
            repairAttempted = true;
            try {
                runRepairScript();
                if (logResult) log.info("event=database.schema.ensure status=ok schema={}", schema());
            } catch (Exception ex) {
                if (logResult) log.warn("event=database.schema.ensure status=failed detail={}", safeMessage(ex));
            }
        }
    }

    private void runRepairScript() throws Exception {
        try {
            jdbcTemplate.execute("create extension if not exists pgcrypto");
        } catch (Exception ignored) {
            // PostgreSQL 16 provides gen_random_uuid() in pg_catalog. Extension
            // creation can be denied by policy, so table creation must continue.
        }

        ClassPathResource resource = new ClassPathResource("db/migration/V2__ensure_todo_service_contract_tables.sql");
        String script;
        try (var input = resource.getInputStream()) {
            script = new String(input.readAllBytes(), StandardCharsets.UTF_8);
        }
        Arrays.stream(script.split(";"))
                .map(String::trim)
                .filter(statement -> !statement.isBlank())
                .filter(statement -> !statement.toLowerCase().contains("create extension"))
                .forEach(jdbcTemplate::execute);
    }

    private boolean checkRequiredTables(boolean logResult) {
        String schema = schema();
        List<String> required = List.of("todos", "todo_history", "outbox_events", "kafka_inbox_events", "access_grant_projections");
        try {
            for (String table : required) {
                String relation = schema + "." + table;
                String found = jdbcTemplate.queryForObject("select to_regclass(?)::text", String.class, relation);
                if (found == null || found.isBlank()) {
                    if (logResult) log.warn("event=database.schema.ready status=down missing_table={}", relation);
                    return false;
                }
            }
            if (logResult) log.info("event=database.schema.ready status=ok schema={}", schema);
            return true;
        } catch (Exception ex) {
            if (logResult) log.warn("event=database.schema.ready status=down detail={}", safeMessage(ex));
            return false;
        }
    }

    private String schema() {
        String schema = properties.getPostgres().getSchema();
        return schema == null || schema.isBlank() ? "todo" : schema.trim();
    }

    private String safeMessage(Exception ex) {
        String message = ex.getMessage();
        return message == null || message.isBlank() ? ex.getClass().getSimpleName() : message.replaceAll("[\r\n]+", " ");
    }
}
