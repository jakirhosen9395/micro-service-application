package com.microservice.todo.health;

import com.microservice.todo.config.TodoProperties;
import com.microservice.todo.observability.DependencyTelemetry;
import jakarta.annotation.PostConstruct;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.index.Index;
import org.springframework.data.mongodb.core.index.IndexOperations;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.CreateBucketRequest;
import software.amazon.awssdk.services.s3.model.HeadBucketRequest;

@Component
public class DependencyInitializer {
    private static final Logger log = LoggerFactory.getLogger(DependencyInitializer.class);
    private static final Duration MONGO_RETRY_DELAY = Duration.ofMinutes(5);

    private final HealthService healthService;
    private final MongoTemplate mongoTemplate;
    private final S3Client s3Client;
    private final TodoProperties properties;
    private final DependencyTelemetry dependencyTelemetry;

    private volatile boolean mongoIndexesReady;
    private volatile Instant nextMongoRetryAt = Instant.EPOCH;

    public DependencyInitializer(
            HealthService healthService,
            MongoTemplate mongoTemplate,
            S3Client s3Client,
            TodoProperties properties,
            DependencyTelemetry dependencyTelemetry) {
        this.healthService = healthService;
        this.mongoTemplate = mongoTemplate;
        this.s3Client = s3Client;
        this.properties = properties;
        this.dependencyTelemetry = dependencyTelemetry;
    }

    @PostConstruct
    public void initializeAtStartup() {
        ensureMongoCollectionAndIndexes();
        ensureS3Bucket();
    }

    @Scheduled(initialDelay = 60000, fixedDelay = 60000)
    public void ensureDependencies() {
        try {
            var postgres = healthService.dependencies().get("postgres");
            log.debug("event=dependency.ensure dependency=postgres status={}", postgres.status());
        } catch (Throwable ex) {
            log.warn("event=dependency.ensure dependency=postgres status=down detail={}", safeMessage(ex));
        }
        ensureMongoCollectionAndIndexes();
        ensureS3Bucket();
    }

    private void ensureMongoCollectionAndIndexes() {
        if (mongoIndexesReady) {
            return;
        }
        Instant now = Instant.now();
        if (now.isBefore(nextMongoRetryAt)) {
            return;
        }
        try {
            dependencyTelemetry.captureVoid("MongoDB ensure log collection indexes", "db", "mongodb", "create_index", this::doEnsureMongoCollectionAndIndexes);
            mongoIndexesReady = true;
            log.debug("event=dependency.ensure dependency=mongodb status=ok collection={}", properties.getMongo().getLogCollection());
        } catch (Throwable ex) {
            nextMongoRetryAt = Instant.now().plus(MONGO_RETRY_DELAY);
            log.warn("event=dependency.ensure dependency=mongodb status=down detail={} retry_after_seconds={}", safeMessage(ex), MONGO_RETRY_DELAY.toSeconds());
        }
    }

    private void doEnsureMongoCollectionAndIndexes() {
        String collection = properties.getMongo().getLogCollection();
        if (!mongoTemplate.collectionExists(collection)) {
            mongoTemplate.createCollection(collection);
        }
        IndexOperations indexes = mongoTemplate.indexOps(collection);
        List<Index> required = List.of(
                new Index().on("timestamp", Sort.Direction.DESC),
                new Index().on("level", Sort.Direction.ASC).on("timestamp", Sort.Direction.DESC),
                new Index().on("event", Sort.Direction.ASC).on("timestamp", Sort.Direction.DESC),
                new Index().on("request_id", Sort.Direction.ASC),
                new Index().on("trace_id", Sort.Direction.ASC),
                new Index().on("user_id", Sort.Direction.ASC).on("timestamp", Sort.Direction.DESC),
                new Index().on("path", Sort.Direction.ASC).on("status_code", Sort.Direction.ASC).on("timestamp", Sort.Direction.DESC),
                new Index().on("error_code", Sort.Direction.ASC).on("timestamp", Sort.Direction.DESC)
        );
        for (Index index : required) {
            indexes.ensureIndex(index);
        }
    }

    private void ensureS3Bucket() {
        try {
            dependencyTelemetry.captureVoid("S3 ensure audit bucket", "storage", "s3", "head_bucket", this::doEnsureS3Bucket);
            log.debug("event=dependency.ensure dependency=s3 status=ok bucket={}", properties.getS3().getBucket());
        } catch (Throwable ex) {
            log.warn("event=dependency.ensure dependency=s3 status=down detail={}", safeMessage(ex));
        }
    }

    private void doEnsureS3Bucket() {
        String bucket = properties.getS3().getBucket();
        try {
            s3Client.headBucket(HeadBucketRequest.builder().bucket(bucket).build());
        } catch (Exception missing) {
            s3Client.createBucket(CreateBucketRequest.builder().bucket(bucket).build());
        }
    }

    private String safeMessage(Throwable ex) {
        String message = ex.getMessage();
        if (message == null || message.isBlank()) {
            message = ex.getClass().getSimpleName();
        }
        return message.replaceAll("[\\r\\n]+", " ");
    }
}
