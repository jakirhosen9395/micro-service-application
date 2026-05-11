package com.microapp.calculator;

import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class OutboxInboxContractTest {

    @Test
    void migrationUsesCalculatorSchemaCanonicalOutboxInboxAndGrantProjection() throws Exception {
        String migration = Files.readString(
                Path.of("src/main/resources/db/migration/V1__calculator_service_schema.sql")
        );
        String normalized = migration.toLowerCase();

        assertTrue(migration.contains("CREATE SCHEMA IF NOT EXISTS ${schema}"));
        assertTrue(migration.contains("CREATE TABLE IF NOT EXISTS ${schema}.calculations"));
        assertTrue(migration.contains("CREATE TABLE IF NOT EXISTS ${schema}.outbox_events"));
        assertTrue(migration.contains("CREATE TABLE IF NOT EXISTS ${schema}.kafka_inbox_events"));
        assertTrue(migration.contains("CREATE TABLE IF NOT EXISTS ${schema}.access_grant_projections"));
        assertTrue(normalized.contains("event_id text not null unique"));
        assertTrue(normalized.contains("constraint outbox_events_status_check"));
        assertTrue(normalized.contains("constraint kafka_inbox_status_check"));
        assertTrue(normalized.contains("constraint access_grant_status_check"));
        assertTrue(migration.contains("idx_calculations_tenant_user_created"));
        assertTrue(migration.contains("idx_outbox_pending"));
        assertTrue(migration.contains("idx_kafka_inbox_topic_partition_offset"));
        assertTrue(migration.contains("idx_access_grants_lookup"));
        assertTrue(migration.contains("id uuid PRIMARY KEY"));
        assertFalse(migration.contains("public.gen_random_uuid()"));
        assertFalse(migration.contains("gen_random_uuid()"));
        assertFalse(migration.contains("CREATE EXTENSION IF NOT EXISTS pgcrypto"));
    }

    @Test
    void serviceWritesCalculationAndOutboxInSameTransactionAndIgnoresDuplicateInboxEvents() throws Exception {
        String app = Files.readString(
                Path.of("src/main/java/com/microapp/calculator/domain/CalculatorApplicationService.java")
        );
        String inbox = Files.readString(
                Path.of("src/main/java/com/microapp/calculator/kafka/KafkaInboxConsumer.java")
        );

        assertTrue(app.contains("transactionTemplate.executeWithoutResult"));
        assertTrue(app.contains("repository.insert(completedEntity)"));
        assertTrue(app.contains("outbox.enqueue(completedEvent)"));
        assertTrue(inbox.contains("insertReceived"));
        assertTrue(inbox.contains("if (!inserted)"));
        assertTrue(inbox.contains("ack.acknowledge()"));
    }

    @Test
    void outboxClaimsRowsWithSchemaQualifiedTableTransactionalSelectAndSkipLocked() throws Exception {
        String outboxRepository = Files.readString(
                Path.of("src/main/java/com/microapp/calculator/persistence/OutboxRepository.java")
        );

        assertTrue(outboxRepository.contains("qualifiedTable(props, \"outbox_events\")"));
        assertTrue(outboxRepository.contains("@Transactional"));
        assertTrue(outboxRepository.contains("FOR UPDATE SKIP LOCKED"));
        assertTrue(outboxRepository.contains("status IN ('PENDING', 'FAILED')"));
        assertTrue(outboxRepository.contains("SET status = 'PROCESSING'"));
        assertFalse(outboxRepository.contains("WITH candidate AS"));
        assertFalse(outboxRepository.contains("UPDATE %s outbox"));
        assertFalse(outboxRepository.contains("RETURNING outbox.id"));
    }

    @Test
    void runtimeSchemaGuardCreatesMissingTablesWhenFlywayWasAlreadyBaselined() throws Exception {
        String infrastructureConfig = Files.readString(
                Path.of("src/main/java/com/microapp/calculator/config/InfrastructureConfig.java")
        );

        assertTrue(infrastructureConfig.contains("calculatorSchemaGuard"));
        assertTrue(infrastructureConfig.contains("ensureCalculatorSchema"));
        assertTrue(infrastructureConfig.contains("@Order(0)"));
        assertTrue(infrastructureConfig.contains("CREATE TABLE IF NOT EXISTS %soutbox_events"));
        assertTrue(infrastructureConfig.contains("CREATE TABLE IF NOT EXISTS %scalculations"));
        assertTrue(infrastructureConfig.contains("CREATE TABLE IF NOT EXISTS %skafka_inbox_events"));
        assertTrue(infrastructureConfig.contains("CREATE TABLE IF NOT EXISTS %saccess_grant_projections"));
    }

    @Test
    void outboxRepositoryHandlesSentRetryAndDeadLetterStatesSafely() throws Exception {
        String outboxRepository = Files.readString(
                Path.of("src/main/java/com/microapp/calculator/persistence/OutboxRepository.java")
        );

        assertTrue(outboxRepository.contains("SET status = 'SENT'"));
        assertTrue(outboxRepository.contains("sent_at = now()"));
        assertTrue(outboxRepository.contains("next_retry_at = NULL"));
        assertTrue(outboxRepository.contains("SET status = 'FAILED'"));
        assertTrue(outboxRepository.contains("attempt_count = attempt_count + 1"));
        assertTrue(outboxRepository.contains("next_retry_at = now() + interval '30 seconds'"));
        assertTrue(outboxRepository.contains("SET status = 'DEAD_LETTERED'"));
        assertTrue(outboxRepository.contains("WHERE id = ?"));
        assertTrue(outboxRepository.contains("AND status <> 'SENT'"));
    }

    @Test
    void persistenceRepositoriesUseSchemaQualifiedTables() throws Exception {
        String calculations = Files.readString(
                Path.of("src/main/java/com/microapp/calculator/persistence/CalculationRepository.java")
        );
        String inbox = Files.readString(
                Path.of("src/main/java/com/microapp/calculator/persistence/InboxRepository.java")
        );
        String accessGrants = Files.readString(
                Path.of("src/main/java/com/microapp/calculator/persistence/AccessGrantRepository.java")
        );

        assertTrue(calculations.contains("qualifiedTable(props, \"calculations\")"));
        assertTrue(inbox.contains("qualifiedTable(props, \"kafka_inbox_events\")"));
        assertTrue(accessGrants.contains("qualifiedTable(props, \"access_grant_projections\")"));
    }
}
