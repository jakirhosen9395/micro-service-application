package com.microapp.calculator.health;

import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.observability.DependencyTelemetry;
import com.mongodb.client.MongoClient;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.AdminClientConfig;
import org.bson.Document;
import org.springframework.data.redis.connection.RedisConnection;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.HeadBucketRequest;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Properties;

@Service
public class HealthService {
    private final AppProperties props;
    private final JdbcTemplate jdbc;
    private final RedisConnectionFactory redisConnectionFactory;
    private final S3Client s3Client;
    private final MongoClient mongoClient;
    private final DependencyTelemetry telemetry;
    private final HttpClient httpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();

    public HealthService(AppProperties props, JdbcTemplate jdbc, RedisConnectionFactory redisConnectionFactory, S3Client s3Client, MongoClient mongoClient, DependencyTelemetry telemetry) {
        this.props = props;
        this.jdbc = jdbc;
        this.redisConnectionFactory = redisConnectionFactory;
        this.s3Client = s3Client;
        this.mongoClient = mongoClient;
        this.telemetry = telemetry;
    }

    public HealthResponse health() {
        Map<String, DependencyResult> dependencies = new LinkedHashMap<>();
        dependencies.put("jwt", timed("JWT_INVALID", () -> {
            if (props.getJwt().getSecret() == null || props.getJwt().getSecret().length() < 32 || !"HS256".equalsIgnoreCase(props.getJwt().getAlgorithm())) {
                throw new IllegalStateException("JWT config invalid");
            }
            return null;
        }));
        dependencies.put("postgres", timed("POSTGRES_UNAVAILABLE", () -> telemetry.capture("db", "postgresql", "query", "postgres SELECT 1", () -> jdbc.queryForObject("select 1", Integer.class))));
        dependencies.put("redis", timed("REDIS_UNAVAILABLE", () -> telemetry.capture("cache", "redis", "ping", "redis PING", () -> {
            try (RedisConnection connection = redisConnectionFactory.getConnection()) {
                connection.ping();
            }
            return null;
        })));
        dependencies.put("kafka", timed("KAFKA_UNAVAILABLE", () -> telemetry.capture("messaging", "kafka", "describe_cluster", "kafka describeCluster", () -> {
            Properties properties = new Properties();
            properties.put(AdminClientConfig.BOOTSTRAP_SERVERS_CONFIG, props.getKafka().getBootstrapServers());
            properties.put(AdminClientConfig.REQUEST_TIMEOUT_MS_CONFIG, "2000");
            try (AdminClient client = AdminClient.create(properties)) {
                client.describeCluster().nodes().get();
            }
            return null;
        })));
        dependencies.put("s3", timed("S3_UNAVAILABLE", () -> telemetry.capture("storage", "s3", "head_bucket", "s3 headBucket " + props.getS3().getBucket(), () -> s3Client.headBucket(HeadBucketRequest.builder().bucket(props.getS3().getBucket()).build()))));
        dependencies.put("mongodb", timed("MONGODB_UNAVAILABLE", () -> telemetry.capture("db", "mongodb", "ping", "mongodb ping", () -> mongoClient.getDatabase(props.getMongo().getDatabase()).runCommand(new Document("ping", 1)))));
        dependencies.put("apm", timed("APM_UNAVAILABLE", () -> telemetry.capture("external", "http", "get", "apm server health", () -> httpGet(props.getApm().getServerUrl(), null, null))));
        dependencies.put("elasticsearch", timed("ELASTICSEARCH_UNAVAILABLE", () -> telemetry.capture("external", "elasticsearch", "get", "elasticsearch health", () -> httpGet(props.getElasticsearch().getUrl(), props.getElasticsearch().getUsername(), props.getElasticsearch().getPassword()))));
        String status = dependencies.values().stream().allMatch(d -> "ok".equals(d.status())) ? "ok" : "down";
        return new HealthResponse(status, props.getServiceName(), props.getVersion(), props.getEnvironment(), Instant.now(), dependencies);
    }

    private DependencyResult timed(String errorCode, HealthAction action) {
        long start = System.nanoTime();
        try {
            action.get();
            return DependencyResult.ok(elapsed(start));
        } catch (Throwable ex) {
            return DependencyResult.down(elapsed(start), errorCode);
        }
    }

    private Object httpGet(String url, String username, String password) throws Exception {
        HttpRequest.Builder builder = HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofSeconds(2)).GET();
        if (username != null && !username.isBlank()) {
            String token = Base64.getEncoder().encodeToString((username + ":" + (password == null ? "" : password)).getBytes(StandardCharsets.UTF_8));
            builder.header("Authorization", "Basic " + token);
        }
        HttpResponse<Void> response = httpClient.send(builder.build(), HttpResponse.BodyHandlers.discarding());
        if (response.statusCode() < 200 || response.statusCode() >= 400) {
            throw new IllegalStateException("HTTP " + response.statusCode());
        }
        return response;
    }

    private double elapsed(long start) {
        return (System.nanoTime() - start) / 1_000_000.0;
    }

    @FunctionalInterface
    private interface HealthAction {
        Object get() throws Exception;
    }
}
