# Migrations

The canonical PostgreSQL migration is packaged for Flyway at:

`src/main/resources/db/migration/V1__todo_list_service_schema.sql`

It creates the `todo` schema, `todos`, `todo_history`, canonical `outbox_events`, and canonical `kafka_inbox_events` tables. The same SQL is duplicated here for operators who prefer to review or apply migrations manually.
