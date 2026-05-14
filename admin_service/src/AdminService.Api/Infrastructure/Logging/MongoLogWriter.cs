using AdminService.Api.Configuration;
using AdminService.Api.Http;
using AdminService.Api.Infrastructure.Observability;
using MongoDB.Bson;
using MongoDB.Driver;
using System.Text.Json;

namespace AdminService.Api.Infrastructure.Logging;

public sealed class MongoLogWriter
{
    private readonly IMongoCollection<BsonDocument> _collection;
    private readonly AdminSettings _settings;

    public MongoLogWriter(IMongoClient client, AdminSettings settings)
    {
        _settings = settings;
        _collection = client.GetDatabase(settings.MongoDatabase).GetCollection<BsonDocument>(settings.MongoLogCollection);
    }

    public async Task EnsureIndexesAsync(CancellationToken cancellationToken)
    {
        var keys = Builders<BsonDocument>.IndexKeys;
        var indexes = new[]
        {
            new CreateIndexModel<BsonDocument>(keys.Descending("timestamp")),
            new CreateIndexModel<BsonDocument>(keys.Ascending("level").Descending("timestamp")),
            new CreateIndexModel<BsonDocument>(keys.Ascending("event").Descending("timestamp")),
            new CreateIndexModel<BsonDocument>(keys.Ascending("request_id")),
            new CreateIndexModel<BsonDocument>(keys.Ascending("trace_id")),
            new CreateIndexModel<BsonDocument>(keys.Ascending("elastic_trace_id")),
            new CreateIndexModel<BsonDocument>(keys.Ascending("user_id").Descending("timestamp")),
            new CreateIndexModel<BsonDocument>(keys.Ascending("path").Ascending("status_code").Descending("timestamp")),
            new CreateIndexModel<BsonDocument>(keys.Ascending("error_code").Descending("timestamp"))
        };
        await ApmTelemetry.CaptureSpanAsync(
            "MongoDB create log indexes",
            "db",
            "mongodb",
            "create_indexes",
            async () =>
            {
                await _collection.Indexes.CreateManyAsync(indexes, cancellationToken);
            },
            MongoLabels("create_indexes", new Dictionary<string, object?>
            {
                ["index_count"] = indexes.Length
            }));
    }

    public async Task WriteAsync(IDictionary<string, object?> document, CancellationToken cancellationToken)
    {
        var json = JsonSerializer.Serialize(document, JsonOptionsFactory.Options);
        var bson = BsonDocument.Parse(json);
        var span = ApmTelemetry.StartSpan(
            "MongoDB insert log",
            "db",
            "mongodb",
            "insert",
            MongoLabels("insert", new Dictionary<string, object?>
            {
                ["payload_bytes"] = json.Length,
                ["log_event"] = document.TryGetValue("event", out var evt) ? evt : null,
                ["log_level"] = document.TryGetValue("level", out var level) ? level : null
            }));

        try
        {
            await _collection.InsertOneAsync(bson, cancellationToken: cancellationToken);
            ApmTelemetry.SetLabel(span, "outcome", "success");
        }
        catch (Exception ex)
        {
            // MongoDB log writes must not create application error storms or make request
            // processing fail. The /health endpoint still reports MongoDB availability.
            ApmTelemetry.SetLabel(span, "outcome", "failure");
            ApmTelemetry.SetLabel(span, "mongo_log_write_failed", true);
            ApmTelemetry.SetLabel(span, "exception_class", ex.GetType().Name);
            Console.Error.WriteLine(JsonSerializer.Serialize(new Dictionary<string, object?>
            {
                ["timestamp"] = DateTimeOffset.UtcNow,
                ["level"] = "WARN",
                ["service"] = _settings.ServiceName,
                ["environment"] = _settings.EnvironmentName,
                ["tenant"] = _settings.Tenant,
                ["event"] = "mongodb.log_write_failed",
                ["message"] = SecretRedactor.SafeExceptionMessage(ex)
            }, JsonOptionsFactory.Options));
        }
        finally
        {
            span?.End();
        }
    }

    private Dictionary<string, object?> MongoLabels(string operation, IDictionary<string, object?>? extra = null)
    {
        var labels = new Dictionary<string, object?>
        {
            ["dependency"] = "mongodb",
            ["db_system"] = "mongodb",
            ["db_operation"] = operation,
            ["db_name"] = _settings.MongoDatabase,
            ["db_collection"] = _settings.MongoLogCollection
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
