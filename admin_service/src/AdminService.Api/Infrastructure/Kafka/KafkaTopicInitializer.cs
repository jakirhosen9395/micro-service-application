using AdminService.Api.Configuration;
using AdminService.Api.Infrastructure.Logging;
using AdminService.Api.Infrastructure.Observability;
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
            await CreateTopicsIfNeededAsync(admin, topics, cancellationToken);
        }

        ApmTelemetry.CaptureSpan(
            "Kafka metadata",
            "messaging",
            "kafka",
            "metadata",
            () => _ = admin.GetMetadata(TimeSpan.FromSeconds(5)),
            KafkaLabels("metadata", topics.Length));
        await _logger.InfoAsync("kafka.topics.ready", "Kafka topics verified", extra: new Dictionary<string, object?> { ["topic_count"] = topics.Length }, cancellationToken: cancellationToken);
    }


    private async Task CreateTopicsIfNeededAsync(IAdminClient admin, TopicSpecification[] topics, CancellationToken cancellationToken)
    {
        var span = ApmTelemetry.StartSpan("Kafka create topics", "messaging", "kafka", "admin", KafkaLabels("create_topics", topics.Length));
        try
        {
            await admin.CreateTopicsAsync(topics);
            ApmTelemetry.SetLabel(span, "outcome", "success");
            ApmTelemetry.SetLabel(span, "topics_created", topics.Length);
        }
        catch (CreateTopicsException ex) when (OnlyTopicAlreadyExists(ex))
        {
            // TopicAlreadyExists is normal when multiple services or environments start against
            // the same Kafka cluster. Do not capture this expected condition as an APM error.
            ApmTelemetry.SetLabel(span, "outcome", "success");
            ApmTelemetry.SetLabel(span, "topics_already_existed", ex.Results.Count);
            await _logger.InfoAsync("kafka.topics.already_exists", "Kafka topics already exist", extra: new Dictionary<string, object?>
            {
                ["topic_count"] = ex.Results.Count
            }, cancellationToken: cancellationToken);
        }
        catch (CreateTopicsException ex)
        {
            ApmTelemetry.SetLabel(span, "outcome", "failure");
            span?.CaptureException(ex);
            throw;
        }
        catch (Exception ex)
        {
            ApmTelemetry.SetLabel(span, "outcome", "failure");
            span?.CaptureException(ex);
            throw;
        }
        finally
        {
            ApmTelemetry.EndSpan(span);
        }
    }

    private static bool OnlyTopicAlreadyExists(CreateTopicsException ex)
    {
        return ex.Results.Count > 0 && ex.Results.All(result =>
            result.Error.Code is ErrorCode.NoError or ErrorCode.TopicAlreadyExists ||
            result.Error.Reason.Contains("already exists", StringComparison.OrdinalIgnoreCase));
    }

    private Dictionary<string, object?> KafkaLabels(string operation, int topicCount)
    {
        return new Dictionary<string, object?>
        {
            ["dependency"] = "kafka",
            ["messaging_system"] = "kafka",
            ["messaging_operation"] = operation,
            ["kafka_bootstrap_servers"] = _settings.KafkaBootstrapServers,
            ["topic_count"] = topicCount
        };
    }
}
