using AdminService.Api.Configuration;
using AdminService.Api.Infrastructure.Logging;
using Confluent.Kafka;
using Confluent.Kafka.Admin;

namespace AdminService.Api.Infrastructure.Kafka;

public sealed class KafkaTopicInitializer
{
    private readonly AdminSettings _settings;
    private readonly AppLogger _logger;

    public KafkaTopicInitializer(AdminSettings settings, AppLogger logger)
    {
        _settings = settings;
        _logger = logger;
    }

    public async Task EnsureTopicsAsync(CancellationToken cancellationToken)
    {
        using var admin = new AdminClientBuilder(new AdminClientConfig { BootstrapServers = _settings.KafkaBootstrapServers }).Build();
        var topics = _settings.KafkaConsumeTopics
            .Concat(new[] { _settings.KafkaEventsTopic, _settings.KafkaDeadLetterTopic, _settings.AuthAdminDecisionsTopic, _settings.AccessEventsTopic })
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .Distinct(StringComparer.Ordinal)
            .Select(topic => new TopicSpecification { Name = topic, NumPartitions = 3, ReplicationFactor = 1 })
            .ToArray();

        if (_settings.KafkaAutoCreateTopics)
        {
            try
            {
                await admin.CreateTopicsAsync(topics);
            }
            catch (CreateTopicsException ex) when (ex.Results.All(r => r.Error.Code is ErrorCode.TopicAlreadyExists or ErrorCode.NoError))
            {
                // Existing topics are expected.
            }
        }

        _ = admin.GetMetadata(TimeSpan.FromSeconds(5));
        await _logger.InfoAsync("kafka.topics.ready", "Kafka topics verified", extra: new Dictionary<string, object?> { ["topic_count"] = topics.Length }, cancellationToken: cancellationToken);
    }
}
