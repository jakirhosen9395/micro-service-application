package com.microservice.todo.config;

import com.microservice.todo.dto.TodoEvent;
import com.mongodb.ConnectionString;
import com.mongodb.MongoClientSettings;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.AdminClientConfig;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;
import java.util.concurrent.TimeUnit;
import org.springframework.boot.mongodb.autoconfigure.MongoClientSettingsBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.mongodb.MongoDatabaseFactory;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.SimpleMongoClientDatabaseFactory;
import org.springframework.kafka.config.ConcurrentKafkaListenerContainerFactory;
import org.springframework.kafka.core.ConsumerFactory;
import org.springframework.kafka.core.DefaultKafkaConsumerFactory;
import org.springframework.kafka.core.DefaultKafkaProducerFactory;
import org.springframework.kafka.core.KafkaAdmin;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.core.ProducerFactory;
import org.springframework.kafka.support.serializer.JsonSerializer;

@Configuration
public class InfrastructureConfig {

    @Bean(destroyMethod = "close")
    MongoClient mongoClient(TodoProperties properties) {
        int timeoutMs = timeoutMs(properties);
        MongoClientSettings settings = MongoClientSettings.builder()
                .applyConnectionString(new ConnectionString(mongoUri(properties)))
                .applyToClusterSettings(cluster -> cluster.serverSelectionTimeout(timeoutMs, TimeUnit.MILLISECONDS))
                .applyToSocketSettings(socket -> socket
                        .connectTimeout(timeoutMs, TimeUnit.MILLISECONDS)
                        .readTimeout(timeoutMs, TimeUnit.MILLISECONDS))
                .build();
        return MongoClients.create(settings);
    }

    @Bean
    MongoDatabaseFactory mongoDatabaseFactory(MongoClient mongoClient, TodoProperties properties) {
        return new SimpleMongoClientDatabaseFactory(mongoClient, properties.getMongo().getDatabase());
    }

    @Bean
    MongoTemplate mongoTemplate(MongoDatabaseFactory mongoDatabaseFactory) {
        return new MongoTemplate(mongoDatabaseFactory);
    }

    @Bean
    MongoClientSettingsBuilderCustomizer mongoTimeoutCustomizer(TodoProperties properties) {
        int timeoutMs = timeoutMs(properties);
        return builder -> builder
                .applyToClusterSettings(settings -> settings.serverSelectionTimeout(timeoutMs, TimeUnit.MILLISECONDS))
                .applyToSocketSettings(settings -> settings
                        .connectTimeout(timeoutMs, TimeUnit.MILLISECONDS)
                        .readTimeout(timeoutMs, TimeUnit.MILLISECONDS));
    }

    @Bean
    KafkaAdmin kafkaAdmin(TodoProperties properties) {
        KafkaAdmin admin = new KafkaAdmin(kafkaCommonConfig(properties));
        admin.setFatalIfBrokerNotAvailable(false);
        admin.setAutoCreate(properties.getKafka().isAutoCreateTopics());
        return admin;
    }

    @Bean(destroyMethod = "close")
    AdminClient kafkaAdminClient(TodoProperties properties) {
        return AdminClient.create(kafkaCommonConfig(properties));
    }

    @Bean
    ConsumerFactory<String, String> consumerFactory(TodoProperties properties) {
        Map<String, Object> props = kafkaCommonConfig(properties);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, properties.getKafka().getConsumerGroup());
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);
        props.put(ConsumerConfig.SESSION_TIMEOUT_MS_CONFIG, Math.max(10000, timeoutMs(properties) * 4));
        props.put(ConsumerConfig.REQUEST_TIMEOUT_MS_CONFIG, Math.max(15000, timeoutMs(properties) * 5));
        props.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, 100);
        return new DefaultKafkaConsumerFactory<>(props);
    }

    @Bean(name = "kafkaListenerContainerFactory")
    ConcurrentKafkaListenerContainerFactory<String, String> kafkaListenerContainerFactory(
            ConsumerFactory<String, String> consumerFactory) {
        ConcurrentKafkaListenerContainerFactory<String, String> factory = new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(consumerFactory);
        factory.setMissingTopicsFatal(false);
        factory.setAutoStartup(false);
        return factory;
    }

    @Bean
    ProducerFactory<String, TodoEvent> producerFactory(TodoProperties properties) {
        Map<String, Object> props = kafkaCommonConfig(properties);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class);
        props.put(JsonSerializer.ADD_TYPE_INFO_HEADERS, false);
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.RETRIES_CONFIG, properties.getKafka().getRetries());
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
        props.put(ProducerConfig.MAX_BLOCK_MS_CONFIG, 3000);
        props.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, timeoutMs(properties));
        props.put(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, Math.max(10000, timeoutMs(properties) * 2));
        props.put(ProducerConfig.LINGER_MS_CONFIG, 5);
        return new DefaultKafkaProducerFactory<>(props);
    }

    @Bean
    KafkaTemplate<String, TodoEvent> kafkaTemplate(ProducerFactory<String, TodoEvent> producerFactory) {
        return new KafkaTemplate<>(producerFactory);
    }

    private Map<String, Object> kafkaCommonConfig(TodoProperties properties) {
        Map<String, Object> props = new HashMap<>();
        props.put(AdminClientConfig.BOOTSTRAP_SERVERS_CONFIG, properties.getKafka().getBootstrapServers());
        props.put(AdminClientConfig.REQUEST_TIMEOUT_MS_CONFIG, timeoutMs(properties));
        props.put(AdminClientConfig.DEFAULT_API_TIMEOUT_MS_CONFIG, Math.max(5000, timeoutMs(properties)));
        return props;
    }


    private String mongoUri(TodoProperties properties) {
        TodoProperties.Mongo mongo = properties.getMongo();
        String host = mongo.getHost() == null || mongo.getHost().isBlank() ? "localhost" : mongo.getHost();
        int port = mongo.getPort();
        String database = mongo.getDatabase() == null || mongo.getDatabase().isBlank() ? "admin" : mongo.getDatabase();
        String authSource = mongo.getAuthSource() == null || mongo.getAuthSource().isBlank() ? "admin" : mongo.getAuthSource();
        String credentials = "";
        if (mongo.getUsername() != null && !mongo.getUsername().isBlank()) {
            credentials = encodeMongoPart(mongo.getUsername()) + ":" + encodeMongoPart(mongo.getPassword()) + "@";
        }
        return "mongodb://" + credentials + host + ":" + port + "/" + encodeMongoPart(database) + "?authSource=" + encodeMongoPart(authSource);
    }

    private String encodeMongoPart(String value) {
        return URLEncoder.encode(value == null ? "" : value, StandardCharsets.UTF_8).replace("+", "%20");
    }

    private int timeoutMs(TodoProperties properties) {
        long seconds = Math.max(1, properties.getHealth().getTimeoutSeconds());
        return (int) Math.min(Integer.MAX_VALUE, seconds * 1000);
    }
}
