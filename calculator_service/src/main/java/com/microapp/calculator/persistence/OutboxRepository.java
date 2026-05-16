package com.microapp.calculator.persistence;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.microapp.calculator.config.AppProperties;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;
import java.util.UUID;

@Repository
public class OutboxRepository {

    private static final int MAX_ERROR_LENGTH = 900;

    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;
    private final CalculatorSchemaInitializer schemaInitializer;
    private final String outboxTable;

    public OutboxRepository(JdbcTemplate jdbc, ObjectMapper mapper, AppProperties props, CalculatorSchemaInitializer schemaInitializer) {
        this.jdbc = jdbc;
        this.mapper = mapper;
        this.schemaInitializer = schemaInitializer;
        this.outboxTable = qualifiedTable(props, "outbox_events");
    }

    public void insert(
            String eventId,
            String tenant,
            String aggregateType,
            String aggregateId,
            String eventType,
            String eventVersion,
            String topic,
            Object envelope,
            String requestId,
            String traceId,
            String correlationId
    ) {
        schemaInitializer.ensure();
        String payload;

        try {
            payload = mapper.writeValueAsString(envelope);
        } catch (Exception ex) {
            throw new IllegalStateException("Unable to serialize outbox envelope", ex);
        }

        jdbc.update("""
                INSERT INTO %s (
                    id,
                    event_id,
                    tenant,
                    aggregate_type,
                    aggregate_id,
                    event_type,
                    event_version,
                    topic,
                    payload,
                    status,
                    request_id,
                    trace_id,
                    correlation_id
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, CAST(? AS jsonb), 'PENDING', ?, ?, ?)
                """.formatted(outboxTable),
                UUID.randomUUID(),
                eventId,
                tenant,
                aggregateType,
                aggregateId,
                eventType,
                eventVersion,
                topic,
                payload,
                requestId,
                traceId,
                correlationId
        );
    }

    @Transactional
    public List<OutboxEventRow> claimPending(int limit) {
        schemaInitializer.ensure();
        int safeLimit = Math.max(1, Math.min(limit, 100));

        List<OutboxEventRow> rows = jdbc.query("""
                SELECT
                    id,
                    event_id,
                    tenant,
                    aggregate_type,
                    aggregate_id,
                    event_type,
                    topic,
                    payload::text AS payload
                FROM %s
                WHERE status IN ('PENDING', 'FAILED')
                  AND (next_retry_at IS NULL OR next_retry_at <= now())
                ORDER BY created_at ASC
                LIMIT ?
                FOR UPDATE SKIP LOCKED
                """.formatted(outboxTable),
                (rs, rowNum) -> mapRow(rs),
                safeLimit
        );

        for (OutboxEventRow row : rows) {
            jdbc.update("""
                    UPDATE %s
                    SET status = 'PROCESSING',
                        updated_at = now()
                    WHERE id = ?
                      AND status IN ('PENDING', 'FAILED')
                    """.formatted(outboxTable),
                    row.id()
            );
        }

        return rows;
    }

    public void markSent(UUID id) {
        schemaInitializer.ensure();
        jdbc.update("""
                UPDATE %s
                SET status = 'SENT',
                    sent_at = now(),
                    updated_at = now(),
                    last_error = NULL,
                    next_retry_at = NULL
                WHERE id = ?
                """.formatted(outboxTable),
                id
        );
    }

    public void markRetry(UUID id, String errorMessage) {
        schemaInitializer.ensure();
        jdbc.update("""
                UPDATE %s
                SET status = 'FAILED',
                    attempt_count = attempt_count + 1,
                    last_error = ?,
                    next_retry_at = now() + interval '30 seconds',
                    updated_at = now()
                WHERE id = ?
                  AND status <> 'SENT'
                """.formatted(outboxTable),
                truncate(errorMessage),
                id
        );
    }

    public void markDeadLettered(UUID id, String errorMessage) {
        schemaInitializer.ensure();
        jdbc.update("""
                UPDATE %s
                SET status = 'DEAD_LETTERED',
                    attempt_count = attempt_count + 1,
                    last_error = ?,
                    next_retry_at = NULL,
                    updated_at = now()
                WHERE id = ?
                  AND status <> 'SENT'
                """.formatted(outboxTable),
                truncate(errorMessage),
                id
        );
    }

    private static OutboxEventRow mapRow(ResultSet rs) throws SQLException {
        return new OutboxEventRow(
                rs.getObject("id", UUID.class),
                rs.getString("event_id"),
                rs.getString("tenant"),
                rs.getString("aggregate_type"),
                rs.getString("aggregate_id"),
                rs.getString("event_type"),
                rs.getString("topic"),
                rs.getString("payload")
        );
    }

    private static String qualifiedTable(AppProperties props, String tableName) {
        String schema = props.getPostgres().getSchema();

        if (schema == null || !schema.matches("[A-Za-z_][A-Za-z0-9_]*")) {
            throw new IllegalStateException("Invalid PostgreSQL schema name for calculator service");
        }

        return schema + "." + tableName;
    }

    private static String truncate(String value) {
        if (value == null) {
            return null;
        }

        return value.length() <= MAX_ERROR_LENGTH ? value : value.substring(0, MAX_ERROR_LENGTH);
    }
}