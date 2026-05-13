package com.microservice.todo.mapper;

import com.microservice.todo.dto.TodoHistoryItem;
import com.microservice.todo.dto.TodoResponse;
import com.microservice.todo.entity.Todo;
import com.microservice.todo.entity.TodoHistory;
import java.util.List;

public final class TodoMapper {
    private TodoMapper() {}

    public static TodoResponse toResponse(Todo todo) {
        return new TodoResponse(
                todo.getId(),
                todo.getUserId(),
                todo.getUsername(),
                todo.getEmail(),
                todo.getTenant(),
                todo.getTitle(),
                todo.getDescription(),
                todo.getStatus(),
                todo.getPriority(),
                todo.getDueDate(),
                todo.getTags() == null ? List.of() : todo.getTags(),
                todo.isArchived(),
                todo.getCompletedAt(),
                todo.getArchivedAt(),
                todo.getDeletedAt(),
                todo.getCreatedAt(),
                todo.getUpdatedAt(),
                todo.getRequestId(),
                todo.getTraceId(),
                todo.getS3ObjectKey()
        );
    }

    public static TodoHistoryItem toHistoryItem(TodoHistory history) {
        return new TodoHistoryItem(
                history.getId(),
                history.getTodoId(),
                history.getUserId(),
                history.getActorId(),
                history.getTenant(),
                history.getEventType(),
                history.getOldStatus(),
                history.getNewStatus(),
                history.getChanges(),
                history.getReason(),
                history.getRequestId(),
                history.getTraceId(),
                history.getClientIp(),
                history.getUserAgent(),
                history.getCreatedAt()
        );
    }
}
