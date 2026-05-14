using Amazon.S3;
using Amazon.S3.Model;
using AdminService.Api.Configuration;
using AdminService.Api.Http;
using AdminService.Api.Infrastructure.Observability;
using AdminService.Api.Persistence;
using Confluent.Kafka;
using Microsoft.EntityFrameworkCore;
using MongoDB.Bson;
using MongoDB.Driver;
using StackExchange.Redis;
using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text;

namespace AdminService.Api.Infrastructure.Health;

public sealed class DependencyHealthService
{
    private readonly AdminSettings _settings;
    private readonly IDbContextFactory<AdminDbContext> _dbFactory;
    private readonly IConnectionMultiplexer _redis;
    private readonly IAmazonS3 _s3;
    private readonly IMongoClient _mongo;
    private readonly IHttpClientFactory _httpClientFactory;

    public DependencyHealthService(AdminSettings settings, IDbContextFactory<AdminDbContext> dbFactory, IConnectionMultiplexer redis, IAmazonS3 s3, IMongoClient mongo, IHttpClientFactory httpClientFactory)
    {
        _settings = settings;
        _dbFactory = dbFactory;
        _redis = redis;
        _s3 = s3;
        _mongo = mongo;
        _httpClientFactory = httpClientFactory;
    }

    public async Task<IResult> CheckAsync(HttpContext http)
    {
        var dependencies = new Dictionary<string, HealthDependency>
        {
            ["jwt"] = await CheckAsync("jwt", "JWT_INVALID", _ => Task.CompletedTask, http.RequestAborted),
            ["postgres"] = await CheckAsync("postgres", "POSTGRES_UNAVAILABLE", CheckPostgresAsync, http.RequestAborted),
            ["redis"] = await CheckAsync("redis", "REDIS_UNAVAILABLE", CheckRedisAsync, http.RequestAborted),
            ["kafka"] = await CheckAsync("kafka", "KAFKA_UNAVAILABLE", CheckKafkaAsync, http.RequestAborted),
            ["s3"] = await CheckAsync("s3", "S3_UNAVAILABLE", CheckS3Async, http.RequestAborted),
            ["mongodb"] = await CheckAsync("mongodb", "MONGODB_UNAVAILABLE", CheckMongoAsync, http.RequestAborted),
            ["apm"] = await CheckAsync("apm", "APM_UNAVAILABLE", CheckApmAsync, http.RequestAborted),
            ["elasticsearch"] = await CheckAsync("elasticsearch", "ELASTICSEARCH_UNAVAILABLE", CheckElasticsearchAsync, http.RequestAborted)
        };

        var status = dependencies.Values.Any(x => x.Status == "down") ? "down" : "ok";
        var body = new
        {
            status,
            service = _settings.ServiceName,
            version = _settings.Version,
            environment = _settings.EnvironmentName,
            timestamp = DateTimeOffset.UtcNow,
            dependencies
        };
        return Results.Json(body, JsonOptionsFactory.Options, statusCode: status == "ok" ? StatusCodes.Status200OK : StatusCodes.Status503ServiceUnavailable);
    }

    private static async Task<HealthDependency> CheckAsync(string dependency, string errorCode, Func<CancellationToken, Task> operation, CancellationToken cancellationToken)
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            await ApmTelemetry.CaptureSpanAsync(
                $"Health check {dependency}",
                DependencyType(dependency),
                dependency,
                "health",
                async () => await operation(cancellationToken),
                new Dictionary<string, object?>
                {
                    ["dependency"] = dependency,
                    ["health_check"] = true
                });
            stopwatch.Stop();
            return new HealthDependency("ok", Math.Round(stopwatch.Elapsed.TotalMilliseconds, 3), null);
        }
        catch
        {
            stopwatch.Stop();
            return new HealthDependency("down", Math.Round(stopwatch.Elapsed.TotalMilliseconds, 3), errorCode);
        }
    }

    private static string DependencyType(string dependency)
    {
        return dependency switch
        {
            "postgres" or "mongodb" => "db",
            "redis" => "cache",
            "kafka" => "messaging",
            "s3" => "storage",
            "apm" or "elasticsearch" => "external",
            _ => "app"
        };
    }

    private async Task CheckPostgresAsync(CancellationToken ct)
    {
        await using var db = await _dbFactory.CreateDbContextAsync(ct);
        await db.Database.ExecuteSqlRawAsync("select 1", ct);
    }

    private async Task CheckRedisAsync(CancellationToken ct)
    {
        await _redis.GetDatabase(_settings.RedisDb).PingAsync();
    }

    private Task CheckKafkaAsync(CancellationToken ct)
    {
        using var admin = new AdminClientBuilder(new AdminClientConfig { BootstrapServers = _settings.KafkaBootstrapServers }).Build();
        _ = admin.GetMetadata(TimeSpan.FromSeconds(5));
        return Task.CompletedTask;
    }

    private async Task CheckS3Async(CancellationToken ct)
    {
        await _s3.ListObjectsV2Async(new ListObjectsV2Request { BucketName = _settings.S3Bucket, MaxKeys = 1 }, ct);
    }

    private async Task CheckMongoAsync(CancellationToken ct)
    {
        var db = _mongo.GetDatabase(_settings.MongoDatabase);
        await db.RunCommandAsync<BsonDocument>(new BsonDocument("ping", 1), cancellationToken: ct);
    }

    private async Task CheckApmAsync(CancellationToken ct)
    {
        var client = _httpClientFactory.CreateClient("apm");
        using var request = new HttpRequestMessage(HttpMethod.Get, _settings.ApmServerUrl);
        if (!string.IsNullOrWhiteSpace(_settings.ApmSecretToken))
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _settings.ApmSecretToken);
        }
        using var response = await client.SendAsync(request, ct);
        if ((int)response.StatusCode >= 500) throw new InvalidOperationException("APM unavailable");
    }

    private async Task CheckElasticsearchAsync(CancellationToken ct)
    {
        var client = _httpClientFactory.CreateClient("elasticsearch");
        using var request = new HttpRequestMessage(HttpMethod.Get, $"{_settings.ElasticsearchUrl.TrimEnd('/')}/_cluster/health");
        var token = Convert.ToBase64String(Encoding.UTF8.GetBytes($"{_settings.ElasticsearchUsername}:{_settings.ElasticsearchPassword}"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Basic", token);
        using var response = await client.SendAsync(request, ct);
        response.EnsureSuccessStatusCode();
    }
}

public sealed record HealthDependency(string Status, double LatencyMs, string? ErrorCode);
