using Xunit;

namespace AdminService.Tests;

public sealed class ContractTests
{
    [Fact]
    public void EnvFilesHaveSameKeysInSameOrder()
    {
        var root = FindRoot();
        var expected = Keys(root, ".env.dev");
        Assert.Equal(expected, Keys(root, ".env.stage"));
        Assert.Equal(expected, Keys(root, ".env.prod"));
        Assert.Equal(expected, Keys(root, ".env.example"));
    }

    [Fact]
    public void EnvFilesDoNotUseForbiddenInfrastructureToggles()
    {
        var root = FindRoot();
        var forbidden = new[]
        {
            "S3_ENABLED", "KAFKA_ENABLED", "REDIS_ENABLED", "POSTGRES_ENABLED", "MONGO_ENABLED", "APM_ENABLED", "SWAGGER_ENABLED",
            "S3_REQUIRED", "KAFKA_REQUIRED", "REDIS_REQUIRED", "POSTGRES_REQUIRED", "MONGO_LOGS_ENABLED"
        };
        foreach (var file in new[] { ".env.dev", ".env.stage", ".env.prod", ".env.example" })
        {
            var text = File.ReadAllText(Path.Combine(root.FullName, file));
            foreach (var token in forbidden)
            {
                Assert.DoesNotContain(token, text, StringComparison.OrdinalIgnoreCase);
            }
            Assert.Contains("ADMIN_LOGSTASH_ENABLED=false", text, StringComparison.Ordinal);
        }
    }

    [Fact]
    public void MigrationContainsCanonicalOutboxAndInboxContracts()
    {
        var root = FindRoot();
        var sql = File.ReadAllText(Path.Combine(root.FullName, "migrations", "001_initial_admin_schema.sql"));
        Assert.Contains("create table if not exists {{schema}}.outbox_events", sql, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("check (status in ('PENDING','PROCESSING','SENT','FAILED','DEAD_LETTERED'))", sql, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("create table if not exists {{schema}}.kafka_inbox_events", sql, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("idx_kafka_inbox_topic_partition_offset", sql, StringComparison.OrdinalIgnoreCase);
    }


    [Fact]
    public void MigrationCreatesAdminSchemaBeforePgcryptoExtension()
    {
        var root = FindRoot();
        var sql = File.ReadAllText(Path.Combine(root.FullName, "migrations", "001_initial_admin_schema.sql"));
        var createSchemaIndex = sql.IndexOf("create schema if not exists {{schema}}", StringComparison.OrdinalIgnoreCase);
        var createExtensionIndex = sql.IndexOf("create extension if not exists pgcrypto", StringComparison.OrdinalIgnoreCase);

        Assert.True(createSchemaIndex >= 0, "Migration must create the service schema before extension setup.");
        Assert.True(createExtensionIndex >= 0, "Migration must create pgcrypto for gen_random_uuid().");
        Assert.True(createSchemaIndex < createExtensionIndex, "Schema creation must happen before pgcrypto extension creation.");
        Assert.Contains("set search_path to {{schema}}, public", sql, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void DockerfileUsesContainerPort8080AndHelloHealthcheck()
    {
        var root = FindRoot();
        var dockerfile = File.ReadAllText(Path.Combine(root.FullName, "Dockerfile"));
        Assert.Contains("EXPOSE 8080", dockerfile, StringComparison.Ordinal);
        Assert.Contains("/hello", dockerfile, StringComparison.Ordinal);
        Assert.Contains("USER appuser", dockerfile, StringComparison.Ordinal);
    }

    private static IReadOnlyList<string> Keys(DirectoryInfo root, string fileName)
    {
        return File.ReadAllLines(Path.Combine(root.FullName, fileName))
            .Select(line => line.Trim())
            .Where(line => line.Length > 0 && !line.StartsWith('#') && line.Contains('='))
            .Select(line => line.Split('=', 2)[0])
            .ToArray();
    }

    private static DirectoryInfo FindRoot()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            if (File.Exists(Path.Combine(current.FullName, ".env.dev"))) return current;
            current = current.Parent;
        }
        throw new InvalidOperationException("Could not locate repository root.");
    }
}
