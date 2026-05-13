package com.microservice.todo.repository;

import com.microservice.todo.entity.OutboxEvent;
import com.microservice.todo.entity.OutboxStatus;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface OutboxEventRepository extends JpaRepository<OutboxEvent, UUID> {
    @Query("""
            select e from OutboxEvent e
            where e.status in :statuses
              and (e.nextRetryAt is null or e.nextRetryAt <= :now)
            order by e.createdAt asc
            """)
    List<OutboxEvent> findReady(
            @Param("statuses") Collection<OutboxStatus> statuses,
            @Param("now") Instant now,
            Pageable pageable);
}
