CREATE SCHEMA IF NOT EXISTS ${schema};


CREATE TABLE IF NOT EXISTS ${schema}.calculations (
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
);

CREATE INDEX IF NOT EXISTS idx_calculations_tenant_user_created
    ON ${schema}.calculations(tenant, user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_calculations_request
    ON ${schema}.calculations(request_id);

CREATE INDEX IF NOT EXISTS idx_calculations_trace
    ON ${schema}.calculations(trace_id);

CREATE INDEX IF NOT EXISTS idx_calculations_status
    ON ${schema}.calculations(status);

CREATE INDEX IF NOT EXISTS idx_calculations_deleted
    ON ${schema}.calculations(deleted_at);

CREATE TABLE IF NOT EXISTS ${schema}.outbox_events (
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
);

CREATE INDEX IF NOT EXISTS idx_outbox_pending
    ON ${schema}.outbox_events(status, next_retry_at, created_at);

CREATE INDEX IF NOT EXISTS idx_outbox_event_type_created
    ON ${schema}.outbox_events(event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_outbox_tenant_created
    ON ${schema}.outbox_events(tenant, created_at DESC);

CREATE TABLE IF NOT EXISTS ${schema}.kafka_inbox_events (
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
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_kafka_inbox_topic_partition_offset
    ON ${schema}.kafka_inbox_events(topic, partition, offset_value);

CREATE INDEX IF NOT EXISTS idx_kafka_inbox_event_type_created
    ON ${schema}.kafka_inbox_events(event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_kafka_inbox_status_created
    ON ${schema}.kafka_inbox_events(status, created_at DESC);

CREATE TABLE IF NOT EXISTS ${schema}.access_grant_projections (
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
);

CREATE INDEX IF NOT EXISTS idx_access_grants_lookup
    ON ${schema}.access_grant_projections(
        tenant,
        target_user_id,
        grantee_user_id,
        scope,
        status,
        expires_at
    );

CREATE INDEX IF NOT EXISTS idx_access_grants_source_event
    ON ${schema}.access_grant_projections(source_event_id);

CREATE INDEX IF NOT EXISTS idx_access_grants_grantee
    ON ${schema}.access_grant_projections(tenant, grantee_user_id, status, expires_at);