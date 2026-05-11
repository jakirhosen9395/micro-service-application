using AdminService.Api.Configuration;
using StackExchange.Redis;
using System.Text.Json;

namespace AdminService.Api.Infrastructure.Redis;

public sealed class AdminCache
{
    private readonly IConnectionMultiplexer _redis;
    private readonly AdminSettings _settings;

    public AdminCache(IConnectionMultiplexer redis, AdminSettings settings)
    {
        _redis = redis;
        _settings = settings;
    }

    public string Key(string suffix) => $"{_settings.EnvironmentName}:{_settings.ServiceName}:{suffix}";

    public async Task<T?> GetAsync<T>(string suffix)
    {
        var value = await _redis.GetDatabase(_settings.RedisDb).StringGetAsync(Key(suffix));
        if (value.IsNullOrEmpty) return default;
        return JsonSerializer.Deserialize<T>(value.ToString(), AdminService.Api.Http.JsonOptionsFactory.Options);
    }

    public async Task SetAsync<T>(string suffix, T value)
    {
        var json = JsonSerializer.Serialize(value, AdminService.Api.Http.JsonOptionsFactory.Options);
        await _redis.GetDatabase(_settings.RedisDb).StringSetAsync(Key(suffix), json, TimeSpan.FromSeconds(_settings.RedisCacheTtlSeconds));
    }

    public Task DeleteAsync(params string[] suffixes)
    {
        var keys = suffixes.Select(s => (RedisKey)Key(s)).ToArray();
        return _redis.GetDatabase(_settings.RedisDb).KeyDeleteAsync(keys);
    }

    public async Task<bool> AcquireLockAsync(string suffix, TimeSpan ttl)
    {
        return await _redis.GetDatabase(_settings.RedisDb).StringSetAsync(Key($"lock:{suffix}"), "1", ttl, When.NotExists);
    }
}
