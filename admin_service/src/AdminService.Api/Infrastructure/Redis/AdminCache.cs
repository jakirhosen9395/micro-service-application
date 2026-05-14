using AdminService.Api.Configuration;
using AdminService.Api.Http;
using AdminService.Api.Infrastructure.Observability;
using StackExchange.Redis;
using System.Text.Json;

namespace AdminService.Api.Infrastructure.Redis;

public sealed class AdminCache
{
    private readonly IConnectionMultiplexer _redis;
    private readonly AdminSettings _settings;

    public AdminCache(IConnectionMultiplexer redis, AdminSettings settings)
    {
        _redis = redis ?? throw new ArgumentNullException(nameof(redis));
        _settings = settings ?? throw new ArgumentNullException(nameof(settings));
    }

    public string Key(string suffix)
    {
        if (string.IsNullOrWhiteSpace(suffix))
        {
            throw new ArgumentException("Redis key suffix is required.", nameof(suffix));
        }

        var normalizedSuffix = suffix.Trim().TrimStart(':');
        return $"{_settings.EnvironmentName}:{_settings.ServiceName}:{normalizedSuffix}";
    }

    public async Task<T?> GetAsync<T>(string suffix)
    {
        var key = Key(suffix);
        var value = await ApmTelemetry.CaptureSpanAsync(
            "Redis GET",
            "cache",
            "redis",
            "get",
            async () =>
            {
                var database = _redis.GetDatabase(_settings.RedisDb);
                return await database.StringGetAsync(key);
            },
            RedisLabels("get", key));

        if (value.IsNullOrEmpty)
        {
            return default;
        }

        var json = value.ToString();
        if (string.IsNullOrWhiteSpace(json))
        {
            return default;
        }

        return JsonSerializer.Deserialize<T>(json, JsonOptionsFactory.Options);
    }

    public async Task SetAsync<T>(string suffix, T value)
    {
        var key = Key(suffix);
        var json = JsonSerializer.Serialize(value, JsonOptionsFactory.Options);
        var ttl = TimeSpan.FromSeconds(Math.Max(1, _settings.RedisCacheTtlSeconds));

        await ApmTelemetry.CaptureSpanAsync(
            "Redis SET",
            "cache",
            "redis",
            "set",
            async () =>
            {
                var database = _redis.GetDatabase(_settings.RedisDb);
                await database.StringSetAsync(key, json, ttl);
            },
            RedisLabels("set", key, new Dictionary<string, object?>
            {
                ["cache_ttl_seconds"] = ttl.TotalSeconds,
                ["payload_bytes"] = json.Length
            }));
    }

    public async Task DeleteAsync(params string[] suffixes)
    {
        if (suffixes.Length == 0)
        {
            return;
        }

        var keys = suffixes
            .Where(suffix => !string.IsNullOrWhiteSpace(suffix))
            .Select(suffix => (RedisKey)Key(suffix))
            .ToArray();

        if (keys.Length == 0)
        {
            return;
        }

        await ApmTelemetry.CaptureSpanAsync(
            "Redis DEL",
            "cache",
            "redis",
            "delete",
            async () =>
            {
                var database = _redis.GetDatabase(_settings.RedisDb);
                await database.KeyDeleteAsync(keys);
            },
            RedisLabels("delete", keys.Length == 1 ? keys[0].ToString() : "multiple", new Dictionary<string, object?>
            {
                ["key_count"] = keys.Length
            }));
    }

    public async Task<bool> AcquireLockAsync(string suffix, TimeSpan ttl)
    {
        var key = Key($"lock:{suffix}");
        var lockTtl = ttl <= TimeSpan.Zero ? TimeSpan.FromSeconds(30) : ttl;

        return await ApmTelemetry.CaptureSpanAsync(
            "Redis LOCK acquire",
            "cache",
            "redis",
            "lock",
            async () =>
            {
                var database = _redis.GetDatabase(_settings.RedisDb);
                return await database.StringSetAsync(
                    key,
                    "1",
                    lockTtl,
                    When.NotExists);
            },
            RedisLabels("lock_acquire", key, new Dictionary<string, object?>
            {
                ["cache_ttl_seconds"] = lockTtl.TotalSeconds
            }));
    }

    public async Task ReleaseLockAsync(string suffix)
    {
        var key = Key($"lock:{suffix}");
        await ApmTelemetry.CaptureSpanAsync(
            "Redis LOCK release",
            "cache",
            "redis",
            "unlock",
            async () =>
            {
                var database = _redis.GetDatabase(_settings.RedisDb);
                await database.KeyDeleteAsync(key);
            },
            RedisLabels("lock_release", key));
    }

    private Dictionary<string, object?> RedisLabels(string operation, string key, IDictionary<string, object?>? extra = null)
    {
        var labels = new Dictionary<string, object?>
        {
            ["dependency"] = "redis",
            ["db_system"] = "redis",
            ["db_operation"] = operation,
            ["redis_database"] = _settings.RedisDb,
            ["redis_key"] = key
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
