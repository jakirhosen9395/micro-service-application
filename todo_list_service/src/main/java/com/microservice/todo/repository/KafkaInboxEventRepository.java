package com.microservice.todo.repository;

import com.microservice.todo.entity.KafkaInboxEvent;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface KafkaInboxEventRepository extends JpaRepository<KafkaInboxEvent, UUID> {
    boolean existsByEventId(String eventId);
    Optional<KafkaInboxEvent> findByTopicAndPartitionAndOffsetValue(String topic, int partition, long offsetValue);
}
