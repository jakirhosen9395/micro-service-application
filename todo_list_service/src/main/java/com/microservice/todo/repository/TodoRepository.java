package com.microservice.todo.repository;

import com.microservice.todo.entity.Todo;
import com.microservice.todo.entity.TodoPriority;
import com.microservice.todo.entity.TodoStatus;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TodoRepository extends JpaRepository<Todo, String>, JpaSpecificationExecutor<Todo> {
    Optional<Todo> findByIdAndUserIdAndTenant(String id, String userId, String tenant);

    @Query("""
            select t from Todo t
            where t.userId = :userId
              and t.tenant = :tenant
              and (:includeDeleted = true or t.deletedAt is null)
              and (:archived is null or t.archived = :archived)
              and (:status is null or t.status = :status)
              and (:priority is null or t.priority = :priority)
              and (:dueAfter is null or t.dueDate >= :dueAfter)
              and (:dueBefore is null or t.dueDate <= :dueBefore)
              and (
                    :search is null
                    or lower(t.title) like lower(concat('%', :search, '%'))
                    or lower(coalesce(t.description, '')) like lower(concat('%', :search, '%'))
                  )
            """)
    Page<Todo> search(
            @Param("userId") String userId,
            @Param("tenant") String tenant,
            @Param("status") TodoStatus status,
            @Param("priority") TodoPriority priority,
            @Param("search") String search,
            @Param("dueAfter") Instant dueAfter,
            @Param("dueBefore") Instant dueBefore,
            @Param("archived") Boolean archived,
            @Param("includeDeleted") boolean includeDeleted,
            Pageable pageable);

    @Query("""
            select t from Todo t
            where t.userId = :userId
              and t.tenant = :tenant
              and t.deletedAt is null
              and t.dueDate is not null
              and t.dueDate < :now
              and t.status not in :terminalStatuses
            order by t.dueDate asc
            """)
    List<Todo> findOverdue(
            @Param("userId") String userId,
            @Param("tenant") String tenant,
            @Param("now") Instant now,
            @Param("terminalStatuses") Collection<TodoStatus> terminalStatuses,
            Pageable pageable);

    @Query("""
            select t from Todo t
            where t.userId = :userId
              and t.tenant = :tenant
              and t.deletedAt is null
              and t.dueDate >= :start
              and t.dueDate < :end
            order by t.dueDate asc
            """)
    List<Todo> findDueBetween(
            @Param("userId") String userId,
            @Param("tenant") String tenant,
            @Param("start") Instant start,
            @Param("end") Instant end,
            Pageable pageable);
}
