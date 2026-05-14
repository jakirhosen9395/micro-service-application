using Amazon.S3;
using Amazon.S3.Model;
using AdminService.Api.Configuration;
using AdminService.Api.Infrastructure.Kafka;
using AdminService.Api.Infrastructure.Logging;
using AdminService.Api.Infrastructure.Observability;
using AdminService.Api.Persistence;
using Elastic.Apm;
using MongoDB.Bson;
using MongoDB.Driver;
using StackExchange.Redis;
using System.Net.Http.Headers;
using System.Text;

namespace AdminService.Api.Infrastructure.Startup;

public sealed class StartupInitializer
{
    private readonly AdminSettings _settings;
    private readonly DatabaseMigrator _migrator;
    private readonly IConnectionMultiplexer _redis;
    private readonly KafkaTopicInitializer _kafkaTopics;
    private readonly IAmazonS3 _s3;
    private readonly IMongoClient _mongo;
    private readonly MongoLogWriter _mongoLogWriter;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly AppLogger _logger;

    public StartupInitializer(AdminSettings settings, DatabaseMigrator migrator, IConnectionMultiplexer redis, KafkaTopicInitializer kafkaTopics, IAmazonS3 s3, IMongoClient mongo, MongoLogWriter mongoLogWriter, IHttpClientFactory httpClientFactory, AppLogger logger)
    {
        _settings = settings;
        _migrator = migrator;
        _redis = redis;
        _kafkaTopics = kafkaTopics;
        _s3 = s3;
        _mongo = mongo;
        _mongoLogWriter = mongoLogWriter;
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    public async Task InitializeAsync(CancellationToken cancellationToken)
    {
        await Agent.Tracer.CaptureTransaction("admin.startup.initialize", "app", async transaction =>
        {
            transaction.SetLabel("service", _settings.ServiceName);
            transaction.SetLabel("environment", _settings.EnvironmentName);
            transaction.SetLabel("tenant", _settings.Tenant);
            await InitializeCoreAsync(cancellationToken);
        });
    }

    private async Task InitializeCoreAsync(CancellationToken cancellationToken)
    {
        await _logger.InfoAsync("application.starting", "admin_service startup sequence started", cancellationToken: cancellationToken);
        await ApmTelemetry.CaptureSpanAsync(
            "Startup PostgreSQL migration",
            "db",
            "postgresql",
            "migration",
            async () => await _migrator.MigrateAsync(cancellationToken),
            StartupLabels("postgresql", "migration"));
        await ApmTelemetry.CaptureSpanAsync(
            "Startup Redis ping",
            "cache",
            "redis",
            "ping",
            async () =>
            {
                await _redis.GetDatabase(_settings.RedisDb).PingAsync();
            },
            StartupLabels("redis", "ping"));
        await ApmTelemetry.CaptureSpanAsync(
            "Startup Kafka topics",
            "messaging",
            "kafka",
            "admin",
            async () => await _kafkaTopics.EnsureTopicsAsync(cancellationToken),
            StartupLabels("kafka", "topics"));
        await EnsureS3BucketAsync(cancellationToken);
        await ApmTelemetry.CaptureSpanAsync(
            "Startup MongoDB ping",
            "db",
            "mongodb",
            "ping",
            async () =>
            {
                await _mongo.GetDatabase(_settings.MongoDatabase).RunCommandAsync<BsonDocument>(new BsonDocument("ping", 1), cancellationToken: cancellationToken);
            },
            StartupLabels("mongodb", "ping"));
        await _mongoLogWriter.EnsureIndexesAsync(cancellationToken);
        await CheckOptionalObservabilityAsync(cancellationToken);
        await _logger.InfoAsync("apm.agent.configured", "Elastic APM agent configured", extra: new Dictionary<string, object?>
        {
            ["service_name"] = _settings.ServiceName,
            ["environment"] = _settings.EnvironmentName,
            ["server_url"] = _settings.ApmServerUrl
        }, cancellationToken: cancellationToken);
        await _logger.InfoAsync("application.started", "admin_service started", extra: new Dictionary<string, object?>
        {
            ["host"] = _settings.Host,
            ["port"] = _settings.Port,
            ["environment"] = _settings.EnvironmentName,
            ["tenant"] = _settings.Tenant
        }, cancellationToken: cancellationToken);
    }

    private async Task EnsureS3BucketAsync(CancellationToken cancellationToken)
    {
        await ApmTelemetry.CaptureSpanAsync(
            "Startup S3 bucket check",
            "storage",
            "s3",
            "bucket_check",
            async () =>
            {
                try
                {
                    await _s3.ListObjectsV2Async(new ListObjectsV2Request { BucketName = _settings.S3Bucket, MaxKeys = 1 }, cancellationToken);
                }
                catch (AmazonS3Exception ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound || ex.ErrorCode == "NoSuchBucket")
                {
                    await _s3.PutBucketAsync(new PutBucketRequest { BucketName = _settings.S3Bucket }, cancellationToken);
                }
            },
            StartupLabels("s3", "bucket_check", new Dictionary<string, object?>
            {
                ["s3_bucket"] = _settings.S3Bucket
            }));
    }

    private async Task CheckOptionalObservabilityAsync(CancellationToken cancellationToken)
    {
        try
        {
            var client = _httpClientFactory.CreateClient("startup-observability");
            using var apmResponse = await ApmTelemetry.CaptureSpanAsync(
                "Startup APM health",
                "external",
                "apm-server",
                "health",
                async () => await client.GetAsync(_settings.ApmServerUrl, cancellationToken),
                StartupLabels("apm", "health"));
            if ((int)apmResponse.StatusCode >= 500)
            {
                await _logger.WarnAsync("apm.health.down", "APM server returned an unhealthy status", errorCode: "APM_UNAVAILABLE", cancellationToken: cancellationToken);
            }
        }
        catch (Exception ex)
        {
            await _logger.WarnAsync("apm.health.down", "APM server unavailable during startup", errorCode: "APM_UNAVAILABLE", extra: new Dictionary<string, object?> { ["message"] = ex.GetType().Name }, cancellationToken: cancellationToken);
        }

        try
        {
            var client = _httpClientFactory.CreateClient("startup-observability");
            using var request = new HttpRequestMessage(HttpMethod.Get, $"{_settings.ElasticsearchUrl.TrimEnd('/')}/_cluster/health");
            var token = Convert.ToBase64String(Encoding.UTF8.GetBytes($"{_settings.ElasticsearchUsername}:{_settings.ElasticsearchPassword}"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Basic", token);
            using var response = await ApmTelemetry.CaptureSpanAsync(
                "Startup Elasticsearch health",
                "external",
                "elasticsearch",
                "health",
                async () => await client.SendAsync(request, cancellationToken),
                StartupLabels("elasticsearch", "health"));
            if (!response.IsSuccessStatusCode)
            {
                await _logger.WarnAsync("elasticsearch.health.down", "Elasticsearch returned an unhealthy status", errorCode: "ELASTICSEARCH_UNAVAILABLE", cancellationToken: cancellationToken);
            }
        }
        catch (Exception ex)
        {
            await _logger.WarnAsync("elasticsearch.health.down", "Elasticsearch unavailable during startup", errorCode: "ELASTICSEARCH_UNAVAILABLE", extra: new Dictionary<string, object?> { ["message"] = ex.GetType().Name }, cancellationToken: cancellationToken);
        }
    }

    private Dictionary<string, object?> StartupLabels(string dependency, string operation, IDictionary<string, object?>? extra = null)
    {
        var labels = new Dictionary<string, object?>
        {
            ["startup"] = true,
            ["dependency"] = dependency,
            ["operation"] = operation,
            ["service"] = _settings.ServiceName,
            ["environment"] = _settings.EnvironmentName,
            ["tenant"] = _settings.Tenant
        };

        if (extra is not null)
        {
            foreach (var item in extra)
            {
                labels[item.Key] = item.Value;
            }
        }

        return labels;
    }
}
