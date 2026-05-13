package com.microservice.todo.repository;

import com.microservice.todo.entity.TodoHistory;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TodoHistoryRepository extends JpaRepository<TodoHistory, String> {
    List<TodoHistory> findByTodoIdAndUserIdOrderByCreatedAtDesc(String todoId, String userId);
}
