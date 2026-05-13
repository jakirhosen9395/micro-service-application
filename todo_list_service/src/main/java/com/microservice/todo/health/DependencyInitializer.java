package com.microservice.todo.health;

import com.microservice.todo.config.TodoProperties;
import jakarta.annotation.PostConstruct;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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
    private final HealthService healthService;
    private final MongoTemplate mongoTemplate;
    private final S3Client s3Client;
    private final TodoProperties properties;

    public DependencyInitializer(HealthService healthService, MongoTemplate mongoTemplate, S3Client s3Client, TodoProperties properties) {
        this.healthService = healthService;
        this.mongoTemplate = mongoTemplate;
        this.s3Client = s3Client;
        this.properties = properties;
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
        } catch (Exception ex) {
            log.warn("event=dependency.ensure dependency=postgres status=down detail={}", ex.getMessage());
        }
        ensureMongoCollectionAndIndexes();
        ensureS3Bucket();
    }

    private void ensureMongoCollectionAndIndexes() {
        try {
            String collection = properties.getMongo().getLogCollection();
            if (!mongoTemplate.collectionExists(collection)) mongoTemplate.createCollection(collection);
            IndexOperations indexes = mongoTemplate.indexOps(collection);
            indexes.ensureIndex(new Index().on("timestamp", Sort.Direction.DESC));
            indexes.ensureIndex(new Index().on("level", Sort.Direction.ASC).on("timestamp", Sort.Direction.DESC));
            indexes.ensureIndex(new Index().on("event", Sort.Direction.ASC).on("timestamp", Sort.Direction.DESC));
            indexes.ensureIndex(new Index().on("request_id", Sort.Direction.ASC));
            indexes.ensureIndex(new Index().on("trace_id", Sort.Direction.ASC));
            indexes.ensureIndex(new Index().on("user_id", Sort.Direction.ASC).on("timestamp", Sort.Direction.DESC));
            indexes.ensureIndex(new Index().on("path", Sort.Direction.ASC).on("status_code", Sort.Direction.ASC).on("timestamp", Sort.Direction.DESC));
            indexes.ensureIndex(new Index().on("error_code", Sort.Direction.ASC).on("timestamp", Sort.Direction.DESC));
            log.debug("event=dependency.ensure dependency=mongodb status=ok collection={}", collection);
        } catch (Exception ex) {
            log.warn("event=dependency.ensure dependency=mongodb status=down detail={}", ex.getMessage());
        }
    }

    private void ensureS3Bucket() {
        try {
            String bucket = properties.getS3().getBucket();
            try {
                s3Client.headBucket(HeadBucketRequest.builder().bucket(bucket).build());
            } catch (Exception missing) {
                s3Client.createBucket(CreateBucketRequest.builder().bucket(bucket).build());
            }
            log.debug("event=dependency.ensure dependency=s3 status=ok bucket={}", bucket);
        } catch (Exception ex) {
            log.warn("event=dependency.ensure dependency=s3 status=down detail={}", ex.getMessage());
        }
    }
}
