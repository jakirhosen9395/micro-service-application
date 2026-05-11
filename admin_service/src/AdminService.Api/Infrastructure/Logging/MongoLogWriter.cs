using AdminService.Api.Configuration;
using AdminService.Api.Http;
using MongoDB.Bson;
using MongoDB.Driver;
using System.Text.Json;

namespace AdminService.Api.Infrastructure.Logging;

public sealed class MongoLogWriter
{
    private readonly IMongoCollection<BsonDocument> _collection;

    public MongoLogWriter(IMongoClient client, AdminSettings settings)
    {
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
            new CreateIndexModel<BsonDocument>(keys.Ascending("user_id").Descending("timestamp")),
            new CreateIndexModel<BsonDocument>(keys.Ascending("path").Ascending("status_code").Descending("timestamp")),
            new CreateIndexModel<BsonDocument>(keys.Ascending("error_code").Descending("timestamp"))
        };
        await _collection.Indexes.CreateManyAsync(indexes, cancellationToken);
    }

    public async Task WriteAsync(IDictionary<string, object?> document, CancellationToken cancellationToken)
    {
        var json = JsonSerializer.Serialize(document, JsonOptionsFactory.Options);
        var bson = BsonDocument.Parse(json);
        await _collection.InsertOneAsync(bson, cancellationToken: cancellationToken);
    }
}
