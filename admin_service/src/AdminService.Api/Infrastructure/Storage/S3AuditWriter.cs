using Amazon.S3;
using Amazon.S3.Model;
using AdminService.Api.Configuration;
using AdminService.Api.Http;
using System.Text.Json;

namespace AdminService.Api.Infrastructure.Storage;

public sealed class S3AuditWriter
{
    private readonly IAmazonS3 _s3;
    private readonly AdminSettings _settings;

    public S3AuditWriter(IAmazonS3 s3, AdminSettings settings)
    {
        _s3 = s3;
        _settings = settings;
    }

    public async Task<string> WriteAsync(string eventType, string eventId, string actorId, object body, CancellationToken cancellationToken)
    {
        var now = DateTimeOffset.UtcNow;
        var slug = eventType.Replace('.', '_').Replace('-', '_');
        var actor = string.IsNullOrWhiteSpace(actorId) ? "unknown" : actorId;
        var prefix = _settings.S3AuditPrefix.Trim('/');
        var key = $"{prefix}/tenant/{_settings.Tenant}/users/{actor}/events/{now:yyyy}/{now:MM}/{now:dd}/{now:HHmmss}_{slug}_{eventId}.json";
        var json = JsonSerializer.Serialize(body, JsonOptionsFactory.Options);
        await _s3.PutObjectAsync(new PutObjectRequest
        {
            BucketName = _settings.S3Bucket,
            Key = key,
            ContentBody = json,
            ContentType = "application/json"
        }, cancellationToken);
        return key;
    }
}
