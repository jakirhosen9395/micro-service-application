package com.microapp.calculator.persistence;

import com.microapp.calculator.config.AppProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Idempotent schema repair for deployments where Flyway was baselined before
 * all calculator tables existed, or where an older image did not create the
 * canonical outbox/inbox tables. This is intentionally conservative: it only
 * creates missing schema objects and never drops or rewrites user data.
 */
@Component
public class CalculatorSchemaInitializer {
    private static final Logger log = LoggerFactory.getLogger(CalculatorSchemaInitializer.class);

    private final JdbcTemplate jdbc;
    private final AppProperties props;
    private final AtomicBoolean initialized = new AtomicBoolean(false);

    public CalculatorSchemaInitializer(JdbcTemplate jdbc, AppProperties props) {
        this.jdbc = jdbc;
        this.props = props;
    }

    public void ensure() {
        if (initialized.get()) {
            return;
        }
        synchronized (initialized) {
            if (initialized.get()) {
                return;
            }
            forceEnsure();
            initialized.set(true);
        }
    }

    public void forceEnsure() {
        String schema = schemaName();
        String prefix = schema + ".";

        jdbc.execute("CREATE SCHEMA IF NOT EXISTS " + schema);
        jdbc.execute("SET search_path TO " + schema + ", public");

        jdbc.execute("""
                CREATE TABLE IF NOT EXISTS %scalculations (
                    id text PRIMARY KEY,
                    tenant text NOT NULL,
                    user_id text NOT NULL,
                    actor_id text NOT NULL,
                    operation text,
                    expression text,
                    operands jsonb NOT NULL DEFAULT '[]'::jsonb,
                    result text,
                    numeric_result numeric,
                    status text NOT NULL,
                    error_code text,
                    error_message text,
                    request_id text,
                    trace_id text,
                    correlation_id text,
                    client_ip text,
                    user_agent text,
                    duration_ms bigint NOT NULL DEFAULT 0,
                    s3_object_key text,
                    created_at timestamptz NOT NULL DEFAULT now(),
                    updated_at timestamptz NOT NULL DEFAULT now(),
                    deleted_at timestamptz,
                    CONSTRAINT calculations_status_check CHECK (status IN ('COMPLETED', 'FAILED'))
                )
                """.formatted(prefix));

        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_calculations_tenant_user_created ON %scalculations(tenant, user_id, created_at DESC)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_calculations_request ON %scalculations(request_id)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_calculations_trace ON %scalculations(trace_id)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_calculations_status ON %scalculations(status)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_calculations_deleted ON %scalculations(deleted_at)".formatted(prefix));

        jdbc.execute("""
                CREATE TABLE IF NOT EXISTS %soutbox_events (
                    id uuid PRIMARY KEY,
                    event_id text NOT NULL UNIQUE,
                    tenant text NOT NULL,
                    aggregate_type text NOT NULL,
                    aggregate_id text NOT NULL,
                    event_type text NOT NULL,
                    event_version text NOT NULL DEFAULT '1.0',
                    topic text NOT NULL,
                    payload jsonb NOT NULL,
                    status text NOT NULL DEFAULT 'PENDING',
                    attempt_count integer NOT NULL DEFAULT 0,
                    last_error text,
                    next_retry_at timestamptz,
                    request_id text,
                    trace_id text,
                    correlation_id text,
                    created_at timestamptz NOT NULL DEFAULT now(),
                    updated_at timestamptz NOT NULL DEFAULT now(),
                    sent_at timestamptz,
                    CONSTRAINT outbox_events_status_check
                        CHECK (status IN ('PENDING', 'PROCESSING', 'SENT', 'FAILED', 'DEAD_LETTERED'))
                )
                """.formatted(prefix));

        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_outbox_pending ON %soutbox_events(status, next_retry_at, created_at)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_outbox_event_type_created ON %soutbox_events(event_type, created_at DESC)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_outbox_tenant_created ON %soutbox_events(tenant, created_at DESC)".formatted(prefix));

        jdbc.execute("""
                CREATE TABLE IF NOT EXISTS %skafka_inbox_events (
                    id uuid PRIMARY KEY,
                    event_id text NOT NULL UNIQUE,
                    tenant text,
                    topic text NOT NULL,
                    partition integer NOT NULL DEFAULT 0,
                    offset_value bigint NOT NULL DEFAULT 0,
                    event_type text NOT NULL,
                    source_service text,
                    payload jsonb,
                    status text NOT NULL DEFAULT 'RECEIVED',
                    processed_at timestamptz,
                    error_message text,
                    created_at timestamptz NOT NULL DEFAULT now(),
                    CONSTRAINT kafka_inbox_status_check
                        CHECK (status IN ('RECEIVED', 'PROCESSING', 'PROCESSED', 'FAILED', 'IGNORED'))
                )
                """.formatted(prefix));

        jdbc.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_kafka_inbox_topic_partition_offset ON %skafka_inbox_events(topic, partition, offset_value)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_kafka_inbox_event_type_created ON %skafka_inbox_events(event_type, created_at DESC)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_kafka_inbox_status_created ON %skafka_inbox_events(status, created_at DESC)".formatted(prefix));

        jdbc.execute("""
                CREATE TABLE IF NOT EXISTS %saccess_grant_projections (
                    grant_id text PRIMARY KEY,
                    tenant text NOT NULL,
                    target_user_id text NOT NULL,
                    grantee_user_id text NOT NULL,
                    scope text NOT NULL,
                    status text NOT NULL,
                    expires_at timestamptz,
                    revoked_at timestamptz,
                    source_event_id text,
                    created_at timestamptz NOT NULL DEFAULT now(),
                    updated_at timestamptz NOT NULL DEFAULT now(),
                    CONSTRAINT access_grant_status_check
                        CHECK (status IN ('APPROVED', 'ACTIVE', 'REVOKED', 'EXPIRED', 'REJECTED', 'CANCELLED'))
                )
                """.formatted(prefix));

        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_access_grants_lookup ON %saccess_grant_projections(tenant, target_user_id, grantee_user_id, scope, status, expires_at)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_access_grants_source_event ON %saccess_grant_projections(source_event_id)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_access_grants_grantee ON %saccess_grant_projections(tenant, grantee_user_id, status, expires_at)".formatted(prefix));

        log.info("event=calculator.schema.ready schema={}", schema);
    }

    private String schemaName() {
        String schema = props.getPostgres().getSchema();
        if (schema == null || !schema.matches("[A-Za-z_][A-Za-z0-9_]*")) {
            throw new IllegalStateException("Invalid PostgreSQL schema name for calculator service");
        }
        return schema;
    }
}
