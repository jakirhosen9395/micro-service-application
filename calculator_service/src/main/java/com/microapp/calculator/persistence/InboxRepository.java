package com.microapp.calculator.persistence;

import com.microapp.calculator.config.AppProperties;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.UUID;

@Repository
public class InboxRepository {
    private final JdbcTemplate jdbc;
    private final String inboxTable;

    public InboxRepository(JdbcTemplate jdbc, AppProperties props) {
        this.jdbc = jdbc;
        this.inboxTable = qualifiedTable(props, "kafka_inbox_events");
    }

    public boolean insertReceived(String eventId, String tenant, String topic, int partition, long offset, String eventType, String sourceService, String payload) {
        try {
            jdbc.update("""
                    INSERT INTO %s (id, event_id, tenant, topic, partition, offset_value, event_type, source_service, payload, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, CAST(? AS jsonb), 'RECEIVED')
                    """.formatted(inboxTable), UUID.randomUUID(), eventId, tenant, topic, partition, offset, eventType, sourceService, payload);
            return true;
        } catch (DuplicateKeyException ex) {
            return false;
        }
    }

    public void markProcessed(String eventId) {
        jdbc.update("UPDATE %s SET status='PROCESSED', processed_at=now() WHERE event_id=?".formatted(inboxTable), eventId);
    }

    public void markIgnored(String eventId) {
        jdbc.update("UPDATE %s SET status='IGNORED', processed_at=now() WHERE event_id=?".formatted(inboxTable), eventId);
    }

    public void markFailed(String eventId, String errorMessage) {
        jdbc.update("UPDATE %s SET status='FAILED', processed_at=now(), error_message=? WHERE event_id=?".formatted(inboxTable), truncate(errorMessage), eventId);
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
        return value.length() <= 900 ? value : value.substring(0, 900);
    }
}
