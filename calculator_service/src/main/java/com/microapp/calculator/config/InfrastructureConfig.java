package com.microapp.calculator.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.microapp.calculator.persistence.CalculatorSchemaInitializer;
import com.microapp.calculator.observability.MongoDriverClassPreloader;
import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.databind.json.JsonMapper;
import com.mongodb.ConnectionString;
import com.mongodb.MongoClientSettings;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.serialization.StringSerializer;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.core.annotation.Order;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.kafka.config.TopicBuilder;
import org.springframework.kafka.core.DefaultKafkaProducerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.core.ProducerFactory;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;

import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

@Configuration
public class InfrastructureConfig {

    @Bean("calculatorObjectMapper")
    @Primary
    public ObjectMapper objectMapper() {
        return JsonMapper.builder()
                .findAndAddModules()
                .propertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)
                .enable(SerializationFeature.INDENT_OUTPUT)
                .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
                .build();
    }

    /**
     * Runtime schema guard for local/dev rebuilds where Flyway V1 was previously baselined
     * or applied before the calculator tables existed. Flyway remains the canonical migration
     * mechanism; this guard is intentionally idempotent and only creates missing objects.
     */
    @Bean
    @Order(0)
    public ApplicationRunner calculatorSchemaGuard(CalculatorSchemaInitializer schemaInitializer) {
        return args -> schemaInitializer.ensure();
    }

    @Bean
    public S3Client s3Client(AppProperties props) {
        AppProperties.S3 s3 = props.getS3();
        return S3Client.builder()
                .endpointOverride(URI.create(s3.getEndpoint()))
                .region(Region.of(s3.getRegion()))
                .credentialsProvider(
                        StaticCredentialsProvider.create(
                                AwsBasicCredentials.create(s3.getAccessKey(), s3.getSecretKey())
                        )
                )
                .serviceConfiguration(
                        S3Configuration.builder()
                                .pathStyleAccessEnabled(s3.isForcePathStyle())
                                .build()
                )
                .build();
    }

    @Bean
    public MongoClient mongoClient(AppProperties props) {
        MongoDriverClassPreloader.preload();
        AppProperties.Mongo mongo = props.getMongo();

        String username = encode(mongo.getUsername());
        String password = encode(mongo.getPassword());
        String authSource = encode(mongo.getAuthSource());

        String uri = "mongodb://"
                + username
                + ":"
                + password
                + "@"
                + mongo.getHost()
                + ":"
                + mongo.getPort()
                + "/?authSource="
                + authSource;

        return MongoClients.create(
                MongoClientSettings.builder()
                        .applyConnectionString(new ConnectionString(uri))
                        .applyToSocketSettings(builder -> builder
                                .connectTimeout(3, java.util.concurrent.TimeUnit.SECONDS)
                                .readTimeout(5, java.util.concurrent.TimeUnit.SECONDS))
                        .applyToClusterSettings(builder -> builder.serverSelectionTimeout(3, java.util.concurrent.TimeUnit.SECONDS))
                        .build()
        );
    }

    @Bean
    public ProducerFactory<String, String> producerFactory(AppProperties props) {
        Map<String, Object> config = new HashMap<>();

        config.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, props.getKafka().getBootstrapServers());
        config.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        config.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        config.put(ProducerConfig.ACKS_CONFIG, "all");
        config.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
        config.put(ProducerConfig.RETRIES_CONFIG, 5);
        config.put(ProducerConfig.LINGER_MS_CONFIG, 10);
        config.put(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, 30000);
        config.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, 10000);
        config.put(ProducerConfig.MAX_BLOCK_MS_CONFIG, 5000);

        return new DefaultKafkaProducerFactory<>(config);
    }

    @Bean
    public KafkaTemplate<String, String> kafkaTemplate(ProducerFactory<String, String> producerFactory) {
        return new KafkaTemplate<>(producerFactory);
    }

    @Bean
    public NewTopic calculatorEventsTopic(AppProperties props) {
        return TopicBuilder.name(props.getKafka().getEventsTopic())
                .partitions(3)
                .replicas(1)
                .build();
    }

    @Bean
    public NewTopic calculatorDeadLetterTopic(AppProperties props) {
        return TopicBuilder.name(props.getKafka().getDeadLetterTopic())
                .partitions(3)
                .replicas(1)
                .build();
    }

    @Bean
    public String[] kafkaConsumeTopics(AppProperties props) {
        return props.getKafka().consumeTopicList().toArray(String[]::new);
    }

    @Bean
    public TransactionTemplate transactionTemplate(PlatformTransactionManager transactionManager) {
        return new TransactionTemplate(transactionManager);
    }

    @Bean
    public ApplicationRunner elasticApmAttacher(AppProperties props) {
        return args -> {
            ElasticApmBootstrap.attach(props);
        };
    }

    private static void ensureCalculatorSchema(JdbcTemplate jdbc, AppProperties props) {
        String schema = schemaName(props);
        String prefix = schema + ".";

        jdbc.execute("CREATE SCHEMA IF NOT EXISTS " + schema);
        jdbc.execute("""
                CREATE TABLE IF NOT EXISTS %scalculations (
                    id text PRIMARY KEY,
                    tenant text NOT NULL,
                    user_id text NOT NULL,
                    actor_id text NOT NULL,
                    operation text,
                    expression text,
                    operands jsonb NOT NULL DEFAULT '[]'::jsonb,
                    result text,
                    numeric_result numeric,
                    status text NOT NULL,
                    error_code text,
                    error_message text,
                    request_id text,
                    trace_id text,
                    correlation_id text,
                    client_ip text,
                    user_agent text,
                    duration_ms bigint NOT NULL DEFAULT 0,
                    s3_object_key text,
                    created_at timestamptz NOT NULL DEFAULT now(),
                    updated_at timestamptz NOT NULL DEFAULT now(),
                    deleted_at timestamptz,
                    CONSTRAINT calculations_status_check CHECK (status IN ('COMPLETED', 'FAILED'))
                )
                """.formatted(prefix));

        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_calculations_tenant_user_created ON %scalculations(tenant, user_id, created_at DESC)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_calculations_request ON %scalculations(request_id)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_calculations_trace ON %scalculations(trace_id)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_calculations_status ON %scalculations(status)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_calculations_deleted ON %scalculations(deleted_at)".formatted(prefix));

        jdbc.execute("""
                CREATE TABLE IF NOT EXISTS %soutbox_events (
                    id uuid PRIMARY KEY,
                    event_id text NOT NULL UNIQUE,
                    tenant text NOT NULL,
                    aggregate_type text NOT NULL,
                    aggregate_id text NOT NULL,
                    event_type text NOT NULL,
                    event_version text NOT NULL DEFAULT '1.0',
                    topic text NOT NULL,
                    payload jsonb NOT NULL,
                    status text NOT NULL DEFAULT 'PENDING',
                    attempt_count integer NOT NULL DEFAULT 0,
                    last_error text,
                    next_retry_at timestamptz,
                    request_id text,
                    trace_id text,
                    correlation_id text,
                    created_at timestamptz NOT NULL DEFAULT now(),
                    updated_at timestamptz NOT NULL DEFAULT now(),
                    sent_at timestamptz,
                    CONSTRAINT outbox_events_status_check
                        CHECK (status IN ('PENDING', 'PROCESSING', 'SENT', 'FAILED', 'DEAD_LETTERED'))
                )
                """.formatted(prefix));

        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_outbox_pending ON %soutbox_events(status, next_retry_at, created_at)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_outbox_event_type_created ON %soutbox_events(event_type, created_at DESC)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_outbox_tenant_created ON %soutbox_events(tenant, created_at DESC)".formatted(prefix));

        jdbc.execute("""
                CREATE TABLE IF NOT EXISTS %skafka_inbox_events (
                    id uuid PRIMARY KEY,
                    event_id text NOT NULL UNIQUE,
                    tenant text,
                    topic text NOT NULL,
                    partition integer NOT NULL DEFAULT 0,
                    offset_value bigint NOT NULL DEFAULT 0,
                    event_type text NOT NULL,
                    source_service text,
                    payload jsonb,
                    status text NOT NULL DEFAULT 'RECEIVED',
                    processed_at timestamptz,
                    error_message text,
                    created_at timestamptz NOT NULL DEFAULT now(),
                    CONSTRAINT kafka_inbox_status_check
                        CHECK (status IN ('RECEIVED', 'PROCESSING', 'PROCESSED', 'FAILED', 'IGNORED'))
                )
                """.formatted(prefix));

        jdbc.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_kafka_inbox_topic_partition_offset ON %skafka_inbox_events(topic, partition, offset_value)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_kafka_inbox_event_type_created ON %skafka_inbox_events(event_type, created_at DESC)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_kafka_inbox_status_created ON %skafka_inbox_events(status, created_at DESC)".formatted(prefix));

        jdbc.execute("""
                CREATE TABLE IF NOT EXISTS %saccess_grant_projections (
                    grant_id text PRIMARY KEY,
                    tenant text NOT NULL,
                    target_user_id text NOT NULL,
                    grantee_user_id text NOT NULL,
                    scope text NOT NULL,
                    status text NOT NULL,
                    expires_at timestamptz,
                    revoked_at timestamptz,
                    source_event_id text,
                    created_at timestamptz NOT NULL DEFAULT now(),
                    updated_at timestamptz NOT NULL DEFAULT now(),
                    CONSTRAINT access_grant_status_check
                        CHECK (status IN ('APPROVED', 'ACTIVE', 'REVOKED', 'EXPIRED', 'REJECTED', 'CANCELLED'))
                )
                """.formatted(prefix));

        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_access_grants_lookup ON %saccess_grant_projections(tenant, target_user_id, grantee_user_id, scope, status, expires_at)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_access_grants_source_event ON %saccess_grant_projections(source_event_id)".formatted(prefix));
        jdbc.execute("CREATE INDEX IF NOT EXISTS idx_access_grants_grantee ON %saccess_grant_projections(tenant, grantee_user_id, status, expires_at)".formatted(prefix));
    }

    private static String schemaName(AppProperties props) {
        String schema = props.getPostgres().getSchema();

        if (schema == null || !schema.matches("[A-Za-z_][A-Za-z0-9_]*")) {
            throw new IllegalStateException("Invalid PostgreSQL schema name for calculator service");
        }

        return schema;
    }

    private static String encode(String value) {
        return URLEncoder.encode(value == null ? "" : value, StandardCharsets.UTF_8);
    }
}
