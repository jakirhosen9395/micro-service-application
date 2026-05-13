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
        if (!_settings.PostgresMigrationMode.Equals("auto", StringComparison.OrdinalIgnoreCase))
        {
            await _logger.InfoAsync("migration.skipped", "PostgreSQL migration mode is not auto", extra: new Dictionary<string, object?> { ["mode"] = _settings.PostgresMigrationMode }, cancellationToken: cancellationToken);
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

        if (!Regex.IsMatch(_settings.PostgresSchema, "^[a-zA-Z_][a-zA-Z0-9_]*$"))
        {
            throw new InvalidOperationException("ADMIN_POSTGRES_SCHEMA contains invalid characters.");
        }

        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        try
        {
            foreach (var file in files)
            {
                var sql = await File.ReadAllTextAsync(file, cancellationToken);
                sql = sql.Replace("{{schema}}", _settings.PostgresSchema, StringComparison.Ordinal);

                // Ensure PostgreSQL always has a selected schema before executing migrations.
                // This prevents CREATE EXTENSION from failing with SQLSTATE 3F000 when the
                // database/user search_path does not include a creatable schema.
                sql = $"create schema if not exists {_settings.PostgresSchema};\n" +
                      $"set search_path to {_settings.PostgresSchema}, public;\n" +
                      sql;

                await using var command = db.Database.GetDbConnection().CreateCommand();
                command.Transaction = transaction.GetDbTransaction();
                command.CommandText = sql;
                command.CommandTimeout = 120;
                await command.ExecuteNonQueryAsync(cancellationToken);
            }

            await transaction.CommitAsync(cancellationToken);
        }
        catch
        {
            await transaction.RollbackAsync(cancellationToken);
            throw;
        }

        await _logger.InfoAsync("migration.completed", "PostgreSQL schema migration completed", extra: new Dictionary<string, object?> { ["migration_count"] = files.Length }, cancellationToken: cancellationToken);
    }
}
