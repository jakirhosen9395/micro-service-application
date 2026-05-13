package com.microservice.todo.config;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.errors.TopicExistsException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@ConditionalOnProperty(prefix = "todo.kafka", name = "auto-create-topics", havingValue = "true", matchIfMissing = true)
public class KafkaTopicConfig {
    private static final Logger log = LoggerFactory.getLogger(KafkaTopicConfig.class);

    /**
     * Best-effort topic creation for topics owned by todo_list_service only.
     *
     * Cross-service topics such as auth.events, admin.events, calculator.events,
     * access.events, user.events, and report.events are consumed by this service but
     * owned by their producer services. If those topics already exist, even with a
     * different partition count, this service must not try to alter them or fail
     * startup. This avoids noisy KafkaAdmin "different partition count" messages and
     * keeps ownership boundaries aligned with the application contract.
     */
    @Bean
    public ApplicationRunner todoOwnedKafkaTopicInitializer(AdminClient adminClient, TodoProperties properties) {
        return args -> ensureOwnedTopics(adminClient, properties);
    }

    private void ensureOwnedTopics(AdminClient adminClient, TodoProperties properties) {
        try {
            Set<String> ownedTopicNames = ownedTopicNames(properties);
            if (ownedTopicNames.isEmpty()) {
                return;
            }

            Set<String> existing = adminClient.listTopics().names().get();
            List<NewTopic> missing = new ArrayList<>();
            int partitions = Math.max(1, properties.getKafka().getTopicPartitions());
            short replicas = (short) Math.max(1, properties.getKafka().getTopicReplicationFactor());

            for (String topicName : ownedTopicNames) {
                if (!existing.contains(topicName)) {
                    missing.add(new NewTopic(topicName, partitions, replicas));
                }
            }

            if (!missing.isEmpty()) {
                adminClient.createTopics(missing).all().get();
                log.info("event=kafka.topic.ensure status=created topics={}", missing.stream().map(NewTopic::name).toList());
            }
        } catch (Exception ex) {
            Throwable cause = ex.getCause();
            if (cause instanceof TopicExistsException || ex instanceof TopicExistsException) {
                return;
            }
            log.warn("event=kafka.topic.ensure status=ignored detail={}", safeMessage(ex));
        }
    }

    private Set<String> ownedTopicNames(TodoProperties properties) {
        Set<String> topics = new LinkedHashSet<>();
        addTopic(topics, properties.getKafka().getEventsTopic());
        addTopic(topics, properties.getKafka().getDeadLetterTopic());
        return topics;
    }

    private void addTopic(Set<String> topics, String topic) {
        if (topic != null && !topic.isBlank()) {
            topics.add(topic.trim());
        }
    }

    private String safeMessage(Exception ex) {
        String message = ex.getMessage();
        return message == null || message.isBlank() ? ex.getClass().getSimpleName() : message;
    }
}
