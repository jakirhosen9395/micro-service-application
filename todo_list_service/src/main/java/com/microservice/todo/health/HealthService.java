package com.microservice.todo.health;

import com.microservice.todo.config.TodoProperties;
import com.microservice.todo.dto.DependencyStatus;
import com.microservice.todo.dto.HealthResponse;
import com.microservice.todo.observability.DependencyTelemetry;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.TimeUnit;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.AdminClientConfig;
import org.apache.kafka.clients.admin.NewTopic;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.CreateBucketRequest;
import software.amazon.awssdk.services.s3.model.HeadBucketRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;

@Service
public class HealthService {
    private final JdbcTemplate jdbcTemplate;
    private final StringRedisTemplate redisTemplate;
    private final MongoTemplate mongoTemplate;
    private final S3Client s3Client;
    private final TodoProperties properties;
    private final HttpClient httpClient;
    private final com.microservice.todo.service.DatabaseSchemaGuard schemaGuard;
    private final DependencyTelemetry dependencyTelemetry;

    public HealthService(
            JdbcTemplate jdbcTemplate,
            StringRedisTemplate redisTemplate,
            MongoTemplate mongoTemplate,
            S3Client s3Client,
            TodoProperties properties,
            com.microservice.todo.service.DatabaseSchemaGuard schemaGuard,
            DependencyTelemetry dependencyTelemetry) {
        this.jdbcTemplate = jdbcTemplate;
        this.redisTemplate = redisTemplate;
        this.mongoTemplate = mongoTemplate;
        this.s3Client = s3Client;
        this.properties = properties;
        this.schemaGuard = schemaGuard;
        this.dependencyTelemetry = dependencyTelemetry;
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(properties.getHealth().getTimeoutSeconds()))
                .build();
    }

    public HealthResponse health() {
        Map<String, DependencyStatus> dependencies = dependencies();
        boolean failed = dependencies.values().stream().anyMatch(status -> !status.healthy());
        return new HealthResponse(
                failed ? "down" : "ok",
                properties.getServiceName(),
                properties.getServiceVersion(),
                displayEnvironment(properties.getEnv()),
                Instant.now(),
                dependencies);
    }

    public Map<String, DependencyStatus> dependencies() {
        Map<String, DependencyStatus> dependencies = new LinkedHashMap<>();
        dependencies.put("jwt", checkJwt());
        dependencies.put("postgres", dependencyTelemetry.capture("PostgreSQL health check", "db", "postgresql", "query", this::checkPostgres));
        dependencies.put("redis", dependencyTelemetry.capture("Redis health check", "cache", "redis", "ping", this::checkRedis));
        dependencies.put("kafka", dependencyTelemetry.capture("Kafka health check", "messaging", "kafka", "admin", this::checkKafka));
        dependencies.put("s3", dependencyTelemetry.capture("S3 health check", "storage", "s3", "head_bucket", this::checkS3));
        dependencies.put("mongodb", dependencyTelemetry.capture("MongoDB health check", "db", "mongodb", "command", this::checkMongo));
        dependencies.put("apm", dependencyTelemetry.capture("APM server health check", "external", "http", "request", this::checkApm));
        dependencies.put("elasticsearch", dependencyTelemetry.capture("Elasticsearch health check", "external", "elasticsearch", "request", () -> checkHttp(properties.getElasticsearch(), "ELASTICSEARCH_UNAVAILABLE")));
        return dependencies;
    }

    private DependencyStatus checkJwt() {
        long start = System.nanoTime();
        var jwt = properties.getJwt();
        if (jwt.getSecret() == null || jwt.getSecret().isBlank()) {
            return down(start, "JWT_SECRET_MISSING");
        }
        if (!"HS256".equalsIgnoreCase(jwt.getAlgorithm())) {
            return down(start, "JWT_ALGORITHM_UNSUPPORTED");
        }
        return ok(start);
    }

    private DependencyStatus checkPostgres() {
        long start = System.nanoTime();
        try {
            Integer result = jdbcTemplate.queryForObject("select 1", Integer.class);
            if (result == null || result != 1) return down(start, "POSTGRES_UNAVAILABLE");
            return schemaGuard.isReady() ? ok(start) : down(start, "POSTGRES_SCHEMA_NOT_READY");
        } catch (Exception ex) {
            return down(start, "POSTGRES_UNAVAILABLE");
        }
    }

    private DependencyStatus checkRedis() {
        long start = System.nanoTime();
        try {
            var factory = redisTemplate.getConnectionFactory();
            if (factory == null) return down(start, "REDIS_UNAVAILABLE");
            try (var connection = factory.getConnection()) {
                connection.ping();
            }
            return ok(start);
        } catch (Exception ex) {
            return down(start, "REDIS_UNAVAILABLE");
        }
    }

    private DependencyStatus checkKafka() {
        long start = System.nanoTime();
        try (AdminClient admin = AdminClient.create(Map.of(
                AdminClientConfig.BOOTSTRAP_SERVERS_CONFIG, properties.getKafka().getBootstrapServers(),
                AdminClientConfig.REQUEST_TIMEOUT_MS_CONFIG, String.valueOf(properties.getHealth().getTimeoutSeconds() * 1000),
                AdminClientConfig.DEFAULT_API_TIMEOUT_MS_CONFIG, String.valueOf(properties.getHealth().getTimeoutSeconds() * 1000)))) {
            List<String> expected = List.of(properties.getKafka().getEventsTopic(), properties.getKafka().getDeadLetterTopic());
            Set<String> topicNames = admin.listTopics().names().get(properties.getHealth().getTimeoutSeconds(), TimeUnit.SECONDS);
            List<String> missing = missingTopics(expected, topicNames);
            if (!missing.isEmpty() && properties.getKafka().isAutoCreateTopics()) {
                List<NewTopic> topics = new ArrayList<>();
                int partitions = Math.max(1, properties.getKafka().getTopicPartitions());
                short replicas = (short) Math.max(1, properties.getKafka().getTopicReplicationFactor());
                for (String topic : missing) topics.add(new NewTopic(topic, partitions, replicas));
                admin.createTopics(topics).all().get(properties.getHealth().getTimeoutSeconds(), TimeUnit.SECONDS);
                topicNames = admin.listTopics().names().get(properties.getHealth().getTimeoutSeconds(), TimeUnit.SECONDS);
                missing = missingTopics(expected, topicNames);
            }
            return missing.isEmpty() ? ok(start) : down(start, "KAFKA_UNAVAILABLE");
        } catch (Exception ex) {
            return down(start, "KAFKA_UNAVAILABLE");
        }
    }

    private List<String> missingTopics(List<String> expected, Set<String> topicNames) {
        List<String> missing = new ArrayList<>();
        for (String topic : expected) {
            if (!topicNames.contains(topic)) missing.add(topic);
        }
        return missing;
    }

    private DependencyStatus checkMongo() {
        long start = System.nanoTime();
        try {
            mongoTemplate.executeCommand("{ ping: 1 }");
            return ok(start);
        } catch (Throwable ex) {
            return down(start, "MONGODB_UNAVAILABLE");
        }
    }

    private DependencyStatus checkS3() {
        long start = System.nanoTime();
        String bucket = properties.getS3().getBucket();
        if (bucket == null || bucket.isBlank()) return down(start, "S3_BUCKET_MISSING");
        try {
            s3Client.headBucket(HeadBucketRequest.builder().bucket(bucket).build());
            return ok(start);
        } catch (S3Exception ex) {
            if (isMissingBucket(ex)) {
                try {
                    s3Client.createBucket(CreateBucketRequest.builder().bucket(bucket).build());
                    s3Client.headBucket(HeadBucketRequest.builder().bucket(bucket).build());
                    return ok(start);
                } catch (Exception createEx) {
                    return down(start, "S3_UNAVAILABLE");
                }
            }
            return down(start, "S3_UNAVAILABLE");
        } catch (Exception ex) {
            return down(start, "S3_UNAVAILABLE");
        }
    }

    private boolean isMissingBucket(S3Exception ex) {
        String code = ex.awsErrorDetails() == null ? "" : ex.awsErrorDetails().errorCode();
        return ex.statusCode() == 404 || "NoSuchBucket".equalsIgnoreCase(code) || "NotFound".equalsIgnoreCase(code);
    }

    private DependencyStatus checkApm() {
        String url = properties.getApm().getServerUrl();
        if (url == null || url.isBlank()) return down(0L, "APM_SERVER_URL_MISSING");
        return checkSimpleHttp(url, null, null, "APM_UNAVAILABLE");
    }

    private DependencyStatus checkHttp(TodoProperties.HttpDependency dependency, String errorCode) {
        if (dependency.getUrl() == null || dependency.getUrl().isBlank()) return new DependencyStatus("down", 0.0, errorCode);
        return checkSimpleHttp(dependency.getUrl(), dependency.getUsername(), dependency.getPassword(), errorCode);
    }

    private DependencyStatus checkSimpleHttp(String url, String username, String password, String errorCode) {
        long start = System.nanoTime();
        try {
            HttpRequest.Builder builder = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .timeout(Duration.ofSeconds(properties.getHealth().getTimeoutSeconds()))
                    .GET();
            if (username != null && !username.isBlank()) {
                String token = Base64.getEncoder().encodeToString((username + ":" + password).getBytes(StandardCharsets.UTF_8));
                builder.header("Authorization", "Basic " + token);
            }
            HttpResponse<Void> response = httpClient.send(builder.build(), HttpResponse.BodyHandlers.discarding());
            int code = response.statusCode();
            return code >= 200 && code < 500 ? ok(start) : down(start, errorCode);
        } catch (Exception ex) {
            return down(start, errorCode);
        }
    }

    private DependencyStatus ok(long startNanos) {
        return DependencyStatus.ok(elapsedMs(startNanos));
    }

    private DependencyStatus down(long startNanos, String errorCode) {
        return DependencyStatus.down(elapsedMs(startNanos), errorCode);
    }

    private double elapsedMs(long startNanos) {
        if (startNanos <= 0) return 0.0;
        return Math.round(((System.nanoTime() - startNanos) / 1_000_000.0) * 100.0) / 100.0;
    }

    private String displayEnvironment(String env) {
        return switch (env == null ? "" : env.toLowerCase()) {
            case "dev", "development" -> "development";
            case "stage", "staging" -> "stage";
            case "prod", "production" -> "production";
            default -> env;
        };
    }
}
