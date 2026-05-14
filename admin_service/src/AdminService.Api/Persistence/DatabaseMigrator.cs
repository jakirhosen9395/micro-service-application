using AdminService.Api.Configuration;
using AdminService.Api.Infrastructure.Logging;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using System.Text.RegularExpressions;

namespace AdminService.Api.Persistence;

public sealed class DatabaseMigrator
{
    private readonly IDbContextFactory<AdminDbContext> _dbFactory;
    private readonly AdminSettings _settings;
    private readonly AppLogger _logger;

    public DatabaseMigrator(IDbContextFactory<AdminDbContext> dbFactory, AdminSettings settings, AppLogger logger)
    {
        _dbFactory = dbFactory;
        _settings = settings;
        _logger = logger;
    }

    public async Task MigrateAsync(CancellationToken cancellationToken)
    {
        ValidateSchemaName();

        if (!_settings.PostgresMigrationMode.Equals("auto", StringComparison.OrdinalIgnoreCase))
        {
            await _logger.InfoAsync("migration.skipped", "PostgreSQL migration mode is not auto", extra: new Dictionary<string, object?> { ["mode"] = _settings.PostgresMigrationMode }, cancellationToken: cancellationToken);
            await EnsureCanonicalInfrastructureSchemaAsync(cancellationToken);
            return;
        }

        await _logger.InfoAsync("migration.started", "PostgreSQL schema migration started", cancellationToken: cancellationToken);
        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        await db.Database.OpenConnectionAsync(cancellationToken);

        var migrationDir = Path.Combine(AppContext.BaseDirectory, "migrations");
        if (!Directory.Exists(migrationDir))
        {
            migrationDir = Path.Combine(Directory.GetCurrentDirectory(), "migrations");
        }
        var files = Directory.Exists(migrationDir)
            ? Directory.GetFiles(migrationDir, "*.sql").OrderBy(x => x, StringComparer.Ordinal).ToArray()
            : Array.Empty<string>();

        if (files.Length == 0) throw new InvalidOperationException("No SQL migration files were found.");

        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        try
        {
            await ExecuteSqlAsync(db, transaction.GetDbTransaction(), BuildInfrastructureBootstrapSql(), cancellationToken);

            foreach (var file in files)
            {
                var sql = await File.ReadAllTextAsync(file, cancellationToken);
                sql = sql.Replace("{{schema}}", _settings.PostgresSchema, StringComparison.Ordinal);

                // Ensure PostgreSQL always has a selected schema before executing migrations.
                // This prevents CREATE EXTENSION from failing with SQLSTATE 3F000 when the
                // database/user search_path does not include a creatable schema.
                sql = BuildSearchPathSql() + "\n" + sql;

                await ExecuteSqlAsync(db, transaction.GetDbTransaction(), sql, cancellationToken);
            }

            // Run the canonical infrastructure DDL again after all migrations. This makes
            // startup self-healing for older deployments where a failed migration left the
            // admin schema without outbox_events or kafka_inbox_events.
            await ExecuteSqlAsync(db, transaction.GetDbTransaction(), BuildInfrastructureBootstrapSql(), cancellationToken);

            await transaction.CommitAsync(cancellationToken);
        }
        catch
        {
            await transaction.RollbackAsync(cancellationToken);
            throw;
        }

        await _logger.InfoAsync("migration.completed", "PostgreSQL schema migration completed", extra: new Dictionary<string, object?> { ["migration_count"] = files.Length }, cancellationToken: cancellationToken);
    }

    public async Task EnsureCanonicalInfrastructureSchemaAsync(CancellationToken cancellationToken)
    {
        ValidateSchemaName();
        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        await db.Database.OpenConnectionAsync(cancellationToken);
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        try
        {
            await ExecuteSqlAsync(db, transaction.GetDbTransaction(), BuildInfrastructureBootstrapSql(), cancellationToken);
            await transaction.CommitAsync(cancellationToken);
        }
        catch
        {
            await transaction.RollbackAsync(cancellationToken);
            throw;
        }
    }

    private void ValidateSchemaName()
    {
        if (!Regex.IsMatch(_settings.PostgresSchema, "^[a-zA-Z_][a-zA-Z0-9_]*$"))
        {
            throw new InvalidOperationException("ADMIN_POSTGRES_SCHEMA contains invalid characters.");
        }
    }

    private async Task ExecuteSqlAsync(AdminDbContext db, System.Data.Common.DbTransaction transaction, string sql, CancellationToken cancellationToken)
    {
        await using var command = db.Database.GetDbConnection().CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        command.CommandTimeout = 120;
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private string BuildSearchPathSql()
        => $"create schema if not exists {_settings.PostgresSchema};\nset search_path to {_settings.PostgresSchema}, public;";

    private string BuildInfrastructureBootstrapSql()
    {
        var schema = _settings.PostgresSchema;
        return $@"
create schema if not exists {schema};
set search_path to {schema}, public;
create extension if not exists pgcrypto with schema {schema};

create table if not exists {schema}.outbox_events (
  id uuid primary key default gen_random_uuid(),
  event_id text not null unique,
  tenant text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  event_type text not null,
  event_version text not null default '1.0',
  topic text not null,
  payload jsonb not null,
  status text not null default 'PENDING',
  attempt_count integer not null default 0,
  last_error text,
  next_retry_at timestamptz,
  request_id text,
  trace_id text,
  correlation_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sent_at timestamptz,
  constraint outbox_events_status_check
    check (status in ('PENDING','PROCESSING','SENT','FAILED','DEAD_LETTERED'))
);

create index if not exists idx_outbox_pending
  on {schema}.outbox_events(status, next_retry_at, created_at);

create table if not exists {schema}.kafka_inbox_events (
  id uuid primary key default gen_random_uuid(),
  event_id text not null unique,
  tenant text,
  topic text not null,
  partition integer not null default 0,
  offset_value bigint not null default 0,
  event_type text not null,
  source_service text,
  payload jsonb,
  status text not null default 'RECEIVED',
  processed_at timestamptz,
  error_message text,
  created_at timestamptz not null default now(),
  constraint kafka_inbox_status_check
    check (status in ('RECEIVED','PROCESSING','PROCESSED','FAILED','IGNORED'))
);

create unique index if not exists idx_kafka_inbox_topic_partition_offset
  on {schema}.kafka_inbox_events(topic, partition, offset_value);
";
    }
}
