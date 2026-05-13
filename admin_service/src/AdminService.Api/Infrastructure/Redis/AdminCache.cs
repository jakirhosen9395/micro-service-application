using AdminService.Api.Configuration;
using AdminService.Api.Http;
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
        var database = _redis.GetDatabase(_settings.RedisDb);
        var value = await database.StringGetAsync(Key(suffix));

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
        var database = _redis.GetDatabase(_settings.RedisDb);
        var json = JsonSerializer.Serialize(value, JsonOptionsFactory.Options);
        var ttl = TimeSpan.FromSeconds(Math.Max(1, _settings.RedisCacheTtlSeconds));

        await database.StringSetAsync(Key(suffix), json, ttl);
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

        var database = _redis.GetDatabase(_settings.RedisDb);
        await database.KeyDeleteAsync(keys);
    }

    public async Task<bool> AcquireLockAsync(string suffix, TimeSpan ttl)
    {
        var database = _redis.GetDatabase(_settings.RedisDb);
        var lockTtl = ttl <= TimeSpan.Zero ? TimeSpan.FromSeconds(30) : ttl;

        return await database.StringSetAsync(
            Key($"lock:{suffix}"),
            "1",
            lockTtl,
            When.NotExists);
    }

    public async Task ReleaseLockAsync(string suffix)
    {
        var database = _redis.GetDatabase(_settings.RedisDb);
        await database.KeyDeleteAsync(Key($"lock:{suffix}"));
    }
}
