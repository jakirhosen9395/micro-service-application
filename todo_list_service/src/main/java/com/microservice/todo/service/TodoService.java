package com.microservice.todo.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.microservice.todo.config.TodoProperties;
import com.microservice.todo.dto.DeleteTodoData;
import com.microservice.todo.dto.StatusChangeData;
import com.microservice.todo.dto.TodoCreateRequest;
import com.microservice.todo.dto.TodoEvent;
import com.microservice.todo.dto.TodoHistoryData;
import com.microservice.todo.dto.TodoPageData;
import com.microservice.todo.dto.TodoResponse;
import com.microservice.todo.dto.TodoUpdateRequest;
import com.microservice.todo.entity.OutboxEvent;
import com.microservice.todo.entity.OutboxStatus;
import com.microservice.todo.entity.Todo;
import com.microservice.todo.entity.TodoHistory;
import com.microservice.todo.entity.TodoPriority;
import com.microservice.todo.entity.TodoStatus;
import com.microservice.todo.exception.ApiException;
import com.microservice.todo.mapper.TodoMapper;
import com.microservice.todo.repository.OutboxEventRepository;
import com.microservice.todo.repository.AccessGrantRepository;
import com.microservice.todo.repository.TodoHistoryRepository;
import com.microservice.todo.repository.TodoRepository;
import com.microservice.todo.security.UserPrincipal;
import com.microservice.todo.util.RequestContext;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import jakarta.persistence.criteria.Predicate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TodoService {
    private static final Map<TodoStatus, Set<TodoStatus>> ALLOWED_TRANSITIONS = new EnumMap<>(TodoStatus.class);
    static {
        ALLOWED_TRANSITIONS.put(TodoStatus.PENDING, Set.of(TodoStatus.IN_PROGRESS, TodoStatus.COMPLETED, TodoStatus.CANCELLED, TodoStatus.ARCHIVED));
        ALLOWED_TRANSITIONS.put(TodoStatus.IN_PROGRESS, Set.of(TodoStatus.COMPLETED, TodoStatus.CANCELLED, TodoStatus.ARCHIVED));
        ALLOWED_TRANSITIONS.put(TodoStatus.COMPLETED, Set.of(TodoStatus.ARCHIVED));
        ALLOWED_TRANSITIONS.put(TodoStatus.CANCELLED, Set.of(TodoStatus.ARCHIVED));
        ALLOWED_TRANSITIONS.put(TodoStatus.ARCHIVED, Set.of(TodoStatus.PENDING));
    }

    private final TodoRepository todoRepository;
    private final TodoHistoryRepository historyRepository;
    private final OutboxEventRepository outboxRepository;
    private final AccessGrantRepository accessGrantRepository;
    private final TodoCacheService cacheService;
    private final MongoLogService mongoLogService;
    private final S3AuditService s3AuditService;
    private final TodoProperties properties;
    private final ObjectMapper objectMapper;

    public TodoService(
            TodoRepository todoRepository,
            TodoHistoryRepository historyRepository,
            OutboxEventRepository outboxRepository,
            AccessGrantRepository accessGrantRepository,
            TodoCacheService cacheService,
            MongoLogService mongoLogService,
            S3AuditService s3AuditService,
            TodoProperties properties,
            ObjectMapper objectMapper) {
        this.todoRepository = todoRepository;
        this.historyRepository = historyRepository;
        this.outboxRepository = outboxRepository;
        this.accessGrantRepository = accessGrantRepository;
        this.cacheService = cacheService;
        this.mongoLogService = mongoLogService;
        this.s3AuditService = s3AuditService;
        this.properties = properties;
        this.objectMapper = objectMapper;
    }

    @Transactional
    public TodoResponse create(TodoCreateRequest request) {
        UserPrincipal user = RequestContext.requiredUser();
        validateTitle(request.title());
        validateDescription(request.description());
        List<String> tags = validateTags(request.tags());
        var metadata = RequestContext.metadata();

        Todo todo = new Todo();
        todo.setUserId(user.getUserId());
        todo.setUsername(user.getUsername());
        todo.setEmail(user.getEmail());
        todo.setTenant(user.getTenant());
        todo.setTitle(request.title().trim());
        todo.setDescription(request.description());
        todo.setPriority(request.priority() == null ? TodoPriority.MEDIUM : request.priority());
        todo.setStatus(TodoStatus.PENDING);
        todo.setDueDate(request.dueDate());
        todo.setTags(tags);
        todo.setArchived(false);
        todo.setMetadata(Map.of("source", "api"));
        todo.setRequestId(metadata.requestId());
        todo.setTraceId(metadata.traceId());
        todo.setCorrelationId(metadata.correlationId());
        todo.setClientIp(metadata.clientIp());
        todo.setUserAgent(metadata.userAgent());

        Todo saved = todoRepository.save(todo);
        TodoResponse response = TodoMapper.toResponse(saved);
        recordChange("TODO_CREATED", "todo.created", saved, null, null, Map.of("todo", response), null);
        cacheService.put(TodoMapper.toResponse(saved));
        return TodoMapper.toResponse(saved);
    }

    @Transactional(readOnly = true)
    public TodoResponse get(String id) {
        UserPrincipal user = RequestContext.requiredUser();
        if (!user.isApprovedAdmin() && !user.isServiceOrSystem()) {
            return cacheService.get(user.getTenant(), user.getUserId(), id).orElseGet(() -> {
                Todo todo = findAuthorized(id, user);
                TodoResponse response = TodoMapper.toResponse(todo);
                cacheService.put(response);
                return response;
            });
        }
        return TodoMapper.toResponse(findAuthorized(id, user));
    }

    @Transactional
    public TodoPageData list(
            TodoStatus status,
            TodoPriority priority,
            String tag,
            String search,
            Boolean archived,
            Instant dueAfter,
            Instant dueBefore,
            boolean includeDeleted,
            int page,
            int size,
            String sort) {
        UserPrincipal user = RequestContext.requiredUser();
        Pageable pageable = PageRequest.of(
                Math.max(page, 0),
                Math.min(Math.max(size, 1), properties.getDefaults().getMaxPageSize()),
                parseSort(sort));
        String normalizedSearch = normalizeSearch(search);
        String cacheKey = cacheService.listKey(user.getTenant(), user.getUserId(), status, priority, tag, normalizedSearch, archived, dueAfter, dueBefore, includeDeleted, page, size, sort);
        var cached = cacheService.getPage(cacheKey);
        if (cached.isPresent()) {
            recordActivity("todo.list.viewed", "todo_list", user.getUserId(), user.getUserId(), Map.of("page", cached.get().page(), "size", cached.get().size(), "returned", cached.get().items().size(), "cache", true));
            return cached.get();
        }
        var result = todoRepository.findAll(listSpecification(user.getUserId(), user.getTenant(), status, priority, normalizedSearch, dueAfter, dueBefore, archived, includeDeleted), pageable);
        List<TodoResponse> items = result.getContent().stream()
                .filter(todo -> matchesTag(todo, tag))
                .map(TodoMapper::toResponse)
                .toList();
        TodoPageData data = new TodoPageData(items, result.getNumber(), result.getSize(), result.getTotalElements(), result.getTotalPages());
        cacheService.putPage(cacheKey, data);
        recordActivity("todo.list.viewed", "todo_list", user.getUserId(), user.getUserId(), Map.of("page", result.getNumber(), "size", result.getSize(), "returned", items.size(), "cache", false));
        return data;
    }

    @Transactional
    public List<TodoResponse> overdue(int limit) {
        UserPrincipal user = RequestContext.requiredUser();
        int boundedLimit = Math.min(Math.max(limit, 1), properties.getDefaults().getMaxPageSize());
        String cacheKey = cacheService.overdueKey(user.getTenant(), user.getUserId(), boundedLimit);
        var cached = cacheService.getTodoList(cacheKey);
        if (cached.isPresent()) {
            recordActivity("todo.list.viewed", "todo_list", user.getUserId(), user.getUserId(), Map.of("kind", "overdue", "returned", cached.get().size(), "cache", true));
            return cached.get();
        }
        var items = todoRepository.findOverdue(user.getUserId(), user.getTenant(), Instant.now(), List.of(TodoStatus.COMPLETED, TodoStatus.CANCELLED, TodoStatus.ARCHIVED), PageRequest.of(0, boundedLimit))
                .stream().map(TodoMapper::toResponse).toList();
        cacheService.putTodoList(cacheKey, items);
        recordActivity("todo.list.viewed", "todo_list", user.getUserId(), user.getUserId(), Map.of("kind", "overdue", "returned", items.size(), "cache", false));
        return items;
    }

    @Transactional
    public List<TodoResponse> dueToday(int limit) {
        UserPrincipal user = RequestContext.requiredUser();
        Instant start = LocalDate.now(ZoneOffset.UTC).atStartOfDay().toInstant(ZoneOffset.UTC);
        Instant end = start.plusSeconds(86_400);
        int boundedLimit = Math.min(Math.max(limit, 1), properties.getDefaults().getMaxPageSize());
        String cacheKey = cacheService.todayKey(user.getTenant(), user.getUserId(), boundedLimit);
        var cached = cacheService.getTodoList(cacheKey);
        if (cached.isPresent()) {
            recordActivity("todo.list.viewed", "todo_list", user.getUserId(), user.getUserId(), Map.of("kind", "today", "returned", cached.get().size(), "cache", true));
            return cached.get();
        }
        var items = todoRepository.findDueBetween(user.getUserId(), user.getTenant(), start, end, PageRequest.of(0, boundedLimit))
                .stream().map(TodoMapper::toResponse).toList();
        cacheService.putTodoList(cacheKey, items);
        recordActivity("todo.list.viewed", "todo_list", user.getUserId(), user.getUserId(), Map.of("kind", "today", "returned", items.size(), "cache", false));
        return items;
    }

    @Transactional
    public TodoResponse update(String id, TodoUpdateRequest request) {
        UserPrincipal user = RequestContext.requiredUser();
        Todo todo = findWritable(id, user);
        ensureNotDeleted(todo);
        TodoResponse before = TodoMapper.toResponse(todo);

        if (request.title() != null) {
            validateTitle(request.title());
            todo.setTitle(request.title().trim());
        }
        if (request.description() != null) {
            validateDescription(request.description());
            todo.setDescription(request.description());
        }
        if (request.priority() != null) todo.setPriority(request.priority());
        if (request.dueDate() != null) todo.setDueDate(request.dueDate());
        if (request.tags() != null) todo.setTags(validateTags(request.tags()));

        Todo saved = todoRepository.save(todo);
        cacheService.evict(saved.getTenant(), saved.getUserId(), saved.getId());
        TodoResponse response = TodoMapper.toResponse(saved);
        recordChange("TODO_UPDATED", "todo.updated", saved, before, saved.getStatus(), Map.of("todo", response), null);
        return response;
    }

    @Transactional
    public StatusChangeData changeStatus(String id, TodoStatus newStatus, String reason) {
        UserPrincipal user = RequestContext.requiredUser();
        Todo todo = findWritable(id, user);
        ensureNotDeleted(todo);
        TodoStatus previous = todo.getStatus();
        TodoResponse before = TodoMapper.toResponse(todo);
        applyStatus(todo, newStatus);
        Todo saved = todoRepository.save(todo);
        cacheService.evict(saved.getTenant(), saved.getUserId(), saved.getId());
        recordChange("TODO_STATUS_CHANGED", "todo.status_changed", saved, before, previous, Map.of("previous_status", previous, "current_status", newStatus), reason);
        return new StatusChangeData(id, previous, newStatus);
    }

    @Transactional
    public TodoResponse complete(String id) {
        UserPrincipal user = RequestContext.requiredUser();
        Todo todo = findWritable(id, user);
        ensureNotDeleted(todo);
        TodoStatus previous = todo.getStatus();
        TodoResponse before = TodoMapper.toResponse(todo);
        applyStatus(todo, TodoStatus.COMPLETED);
        Todo saved = todoRepository.save(todo);
        cacheService.evict(saved.getTenant(), saved.getUserId(), saved.getId());
        TodoResponse response = TodoMapper.toResponse(saved);
        recordChange("TODO_COMPLETED", "todo.completed", saved, before, previous, Map.of("todo", response), null);
        return response;
    }

    @Transactional
    public TodoResponse archive(String id) {
        UserPrincipal user = RequestContext.requiredUser();
        Todo todo = findWritable(id, user);
        ensureNotDeleted(todo);
        TodoStatus previous = todo.getStatus();
        TodoResponse before = TodoMapper.toResponse(todo);
        applyStatus(todo, TodoStatus.ARCHIVED);
        Todo saved = todoRepository.save(todo);
        cacheService.evict(saved.getTenant(), saved.getUserId(), saved.getId());
        TodoResponse response = TodoMapper.toResponse(saved);
        recordChange("TODO_ARCHIVED", "todo.archived", saved, before, previous, Map.of("todo", response), null);
        return response;
    }

    @Transactional
    public TodoResponse restore(String id) {
        UserPrincipal user = RequestContext.requiredUser();
        Todo todo = findWritable(id, user);
        TodoStatus previous = todo.getStatus();
        TodoResponse before = TodoMapper.toResponse(todo);
        todo.setDeletedAt(null);
        todo.setArchived(false);
        todo.setArchivedAt(null);
        if (todo.getStatus() == TodoStatus.ARCHIVED) todo.setStatus(TodoStatus.PENDING);
        Todo saved = todoRepository.save(todo);
        cacheService.evict(saved.getTenant(), saved.getUserId(), saved.getId());
        TodoResponse response = TodoMapper.toResponse(saved);
        recordChange("TODO_RESTORED", "todo.restored", saved, before, previous, Map.of("todo", response), null);
        return response;
    }

    @Transactional
    public DeleteTodoData softDelete(String id) {
        UserPrincipal user = RequestContext.requiredUser();
        Todo todo = findWritable(id, user);
        TodoResponse before = TodoMapper.toResponse(todo);
        if (todo.getDeletedAt() == null) {
            todo.setDeletedAt(Instant.now());
            todoRepository.save(todo);
            cacheService.evict(todo.getTenant(), todo.getUserId(), id);
            recordChange("TODO_DELETED", "todo.deleted", todo, before, todo.getStatus(), Map.of("deleted_at", todo.getDeletedAt().toString()), null);
        }
        return new DeleteTodoData(id, true, false, todo.getDeletedAt());
    }

    @Transactional
    public DeleteTodoData hardDelete(String id) {
        UserPrincipal user = RequestContext.requiredUser();
        if (!user.isServiceOrSystem() && !user.isApprovedAdmin()) {
            throw ApiException.forbidden("Hard delete requires approved admin or service token");
        }
        Todo todo = findPrivileged(id, user);
        TodoResponse before = TodoMapper.toResponse(todo);
        Instant deletedAt = Instant.now();
        recordChange("TODO_HARD_DELETED", "todo.hard_deleted", todo, before, todo.getStatus(), Map.of("hard_deleted_at", deletedAt.toString()), null);
        todoRepository.delete(todo);
        cacheService.evict(todo.getTenant(), todo.getUserId(), id);
        return new DeleteTodoData(id, true, true, deletedAt);
    }

    @Transactional
    public TodoHistoryData history(String id) {
        UserPrincipal user = RequestContext.requiredUser();
        Todo todo = findAuthorized(id, user, "todo:history:read");
        var cached = cacheService.getHistory(todo.getTenant(), id);
        if (cached.isPresent()) {
            recordActivity("todo.history.viewed", "todo", id, todo.getUserId(), Map.of("history_count", cached.get().items().size(), "cache", true));
            return cached.get();
        }
        var items = historyRepository.findByTodoIdAndUserIdOrderByCreatedAtDesc(id, todo.getUserId())
                .stream().map(TodoMapper::toHistoryItem).toList();
        TodoHistoryData data = new TodoHistoryData(id, items);
        cacheService.putHistory(todo.getTenant(), id, data);
        recordActivity("todo.history.viewed", "todo", id, todo.getUserId(), Map.of("history_count", items.size(), "cache", false));
        return data;
    }

    private Todo findAuthorized(String id, UserPrincipal user) {
        return findAuthorized(id, user, "todo:read");
    }

    private Todo findAuthorized(String id, UserPrincipal user, String scope) {
        Todo todo = todoRepository.findById(id).orElseThrow(() -> ApiException.notFound("Todo not found"));
        if (canRead(todo, user, scope)) return todo;
        throw ApiException.forbidden("You cannot access this todo");
    }

    private Todo findWritable(String id, UserPrincipal user) {
        Todo todo = todoRepository.findById(id).orElseThrow(() -> ApiException.notFound("Todo not found"));
        if (todo.getUserId().equals(user.getUserId()) && todo.getTenant().equals(user.getTenant())) return todo;
        if (user.isApprovedAdmin() || user.isServiceOrSystem()) return todo;
        throw ApiException.forbidden("You cannot modify this todo");
    }

    private Todo findPrivileged(String id, UserPrincipal user) {
        Todo todo = todoRepository.findById(id).orElseThrow(() -> ApiException.notFound("Todo not found"));
        if (user.isApprovedAdmin() || user.isServiceOrSystem()) return todo;
        throw ApiException.forbidden("You cannot perform this privileged todo operation");
    }

    private boolean canRead(Todo todo, UserPrincipal user, String scope) {
        if (todo.getUserId().equals(user.getUserId()) && todo.getTenant().equals(user.getTenant())) return true;
        if (user.isApprovedAdmin() || user.isServiceOrSystem()) return true;
        return accessGrantRepository.hasActiveGrant(todo.getTenant(), todo.getUserId(), user.getUserId(), scope);
    }

    private void ensureNotDeleted(Todo todo) {
        if (todo.getDeletedAt() != null) throw ApiException.badRequest("Todo is deleted. Restore it before updating.");
    }

    private void applyStatus(Todo todo, TodoStatus newStatus) {
        if (newStatus == null) throw ApiException.badRequest("status is required");
        TodoStatus previous = todo.getStatus();
        if (previous == newStatus) return;
        if (!ALLOWED_TRANSITIONS.getOrDefault(previous, Set.of()).contains(newStatus)) {
            throw ApiException.invalidTransition("Invalid status transition from " + previous + " to " + newStatus);
        }
        todo.setStatus(newStatus);
        if (newStatus == TodoStatus.COMPLETED) todo.setCompletedAt(Instant.now());
        if (newStatus == TodoStatus.ARCHIVED) {
            todo.setArchived(true);
            todo.setArchivedAt(Instant.now());
        }
        if (previous == TodoStatus.ARCHIVED && newStatus != TodoStatus.ARCHIVED) {
            todo.setArchived(false);
            todo.setArchivedAt(null);
        }
    }

    private void recordChange(String action, String eventType, Todo todo, TodoResponse before, TodoStatus oldStatus, Map<String, Object> data, String reason) {
        UserPrincipal actor = RequestContext.requiredUser();
        var metadata = RequestContext.metadata();
        String eventId = UUID.randomUUID().toString();
        TodoResponse response = TodoMapper.toResponse(todo);
        Map<String, Object> payload = eventPayload(todo, data);
        TodoEvent event = new TodoEvent(
                eventId,
                eventType,
                "1.0",
                properties.getServiceName(),
                properties.getEnv(),
                todo.getTenant(),
                Instant.now(),
                metadata.requestId(),
                metadata.traceId(),
                metadata.correlationId(),
                todo.getUserId(),
                actor.getUserId(),
                "todo",
                todo.getId(),
                payload);
        Map<String, Object> eventMap = objectMapper.convertValue(event, new com.fasterxml.jackson.core.type.TypeReference<Map<String, Object>>() {});

        TodoHistory history = new TodoHistory();
        history.setTodoId(todo.getId());
        history.setUserId(todo.getUserId());
        history.setActorId(actor.getUserId());
        history.setActorRole(actor.getRole());
        history.setTenant(todo.getTenant());
        history.setAction(action);
        history.setEventType(eventType);
        history.setEventId(eventId);
        history.setOldStatus(oldStatus == null ? null : oldStatus.name());
        history.setNewStatus(todo.getStatus() == null ? null : todo.getStatus().name());
        history.setOldValue(before == null ? null : toJson(before));
        history.setNewValue(toJson(response));
        history.setChanges(data == null ? Map.of() : data);
        history.setReason(reason);
        history.setPayload(eventMap);
        history.setRequestId(metadata.requestId());
        history.setTraceId(metadata.traceId());
        history.setCorrelationId(metadata.correlationId());
        history.setClientIp(metadata.clientIp());
        history.setUserAgent(metadata.userAgent());
        historyRepository.save(history);

        saveOutbox(event, properties.getKafka().getEventsTopic());
        S3AuditResult audit = s3AuditService.writeSnapshot(event, response);
        if (audit.written()) {
            todo.setS3ObjectKey(audit.objectKey());
            saveOutbox(auditEvent("todo.audit.s3_written", event, Map.of("s3_object_key", audit.objectKey())), properties.getKafka().getEventsTopic());
        } else {
            saveOutbox(auditEvent("todo.audit.s3_failed", event, Map.of("error_code", audit.errorCode())), properties.getKafka().getEventsTopic());
        }
        mongoLogService.log(eventType, todo.getId(), todo.getUserId(), data);
    }

    private void recordActivity(String eventType, String aggregateType, String aggregateId, String userId, Map<String, Object> data) {
        UserPrincipal actor = RequestContext.requiredUser();
        var metadata = RequestContext.metadata();
        String eventId = UUID.randomUUID().toString();
        TodoEvent event = new TodoEvent(
                eventId,
                eventType,
                "1.0",
                properties.getServiceName(),
                properties.getEnv(),
                actor.getTenant(),
                Instant.now(),
                metadata.requestId(),
                metadata.traceId(),
                metadata.correlationId(),
                userId,
                actor.getUserId(),
                aggregateType,
                aggregateId,
                data);
        saveOutbox(event, properties.getKafka().getEventsTopic());
        S3AuditResult audit = s3AuditService.writeActivitySnapshot(event, actor, aggregateId, data);
        if (audit.written()) {
            saveOutbox(auditEvent("todo.audit.s3_written", event, Map.of("s3_object_key", audit.objectKey())), properties.getKafka().getEventsTopic());
        } else {
            saveOutbox(auditEvent("todo.audit.s3_failed", event, Map.of("error_code", audit.errorCode())), properties.getKafka().getEventsTopic());
        }
        mongoLogService.log(eventType, aggregateId, userId, data);
    }

    private TodoEvent auditEvent(String eventType, TodoEvent source, Map<String, Object> payload) {
        return new TodoEvent(
                UUID.randomUUID().toString(),
                eventType,
                "1.0",
                properties.getServiceName(),
                displayEnvironment(properties.getEnv()),
                source.tenant(),
                Instant.now(),
                source.requestId(),
                source.traceId(),
                source.correlationId(),
                source.userId(),
                source.actorId(),
                source.aggregateType(),
                source.aggregateId(),
                payload == null ? Map.of() : payload);
    }

    private void saveOutbox(TodoEvent event, String topic) {
        OutboxEvent outbox = new OutboxEvent();
        outbox.setEventId(event.eventId());
        outbox.setTenant(event.tenant());
        outbox.setAggregateId(event.aggregateId());
        outbox.setAggregateType(event.aggregateType());
        outbox.setEventType(event.eventType());
        outbox.setEventVersion(event.eventVersion());
        outbox.setTopic(topic);
        outbox.setPayload(objectMapper.convertValue(event, new com.fasterxml.jackson.core.type.TypeReference<Map<String, Object>>() {}));
        outbox.setStatus(OutboxStatus.PENDING);
        outbox.setRequestId(event.requestId());
        outbox.setTraceId(event.traceId());
        outbox.setCorrelationId(event.correlationId());
        outboxRepository.save(outbox);
    }

    private Map<String, Object> eventPayload(Todo todo, Map<String, Object> extra) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("todo_id", todo.getId());
        payload.put("title", todo.getTitle());
        payload.put("description", todo.getDescription());
        payload.put("status", todo.getStatus());
        payload.put("priority", todo.getPriority());
        payload.put("due_date", todo.getDueDate());
        payload.put("tags", todo.getTags());
        payload.put("extra", extra == null ? Map.of() : extra);
        return payload;
    }


    private String displayEnvironment(String env) {
        return switch (env == null ? "" : env.toLowerCase()) {
            case "dev", "development" -> "development";
            case "stage", "staging" -> "stage";
            case "prod", "production" -> "production";
            default -> env;
        };
    }
    private String toJson(Object value) {
        try { return objectMapper.writeValueAsString(value); }
        catch (JsonProcessingException ex) { return "{}"; }
    }

    private void validateTitle(String title) {
        if (title == null || title.isBlank()) throw ApiException.badRequest("title is required");
        if (title.length() > properties.getValidation().getTitleMaxLength()) throw ApiException.badRequest("title is too long");
    }

    private void validateDescription(String description) {
        if (description != null && description.length() > properties.getValidation().getDescriptionMaxLength()) {
            throw ApiException.badRequest("description is too long");
        }
    }

    private List<String> validateTags(List<String> tags) {
        if (tags == null) return List.of();
        if (tags.size() > properties.getValidation().getMaxTags()) throw ApiException.badRequest("too many tags");
        List<String> cleaned = new ArrayList<>();
        for (String tag : tags) {
            if (tag == null || tag.isBlank()) continue;
            String value = tag.trim();
            if (value.length() > properties.getValidation().getTagMaxLength()) throw ApiException.badRequest("tag is too long");
            cleaned.add(value);
        }
        return List.copyOf(cleaned);
    }

    private Specification<Todo> listSpecification(
            String userId,
            String tenant,
            TodoStatus status,
            TodoPriority priority,
            String search,
            Instant dueAfter,
            Instant dueBefore,
            Boolean archived,
            boolean includeDeleted) {
        return (root, query, cb) -> {
            List<Predicate> predicates = new ArrayList<>();
            predicates.add(cb.equal(root.get("userId"), userId));
            predicates.add(cb.equal(root.get("tenant"), tenant));
            if (!includeDeleted) {
                predicates.add(cb.isNull(root.get("deletedAt")));
            }
            if (archived != null) {
                predicates.add(cb.equal(root.get("archived"), archived));
            }
            if (status != null) {
                predicates.add(cb.equal(root.get("status"), status));
            }
            if (priority != null) {
                predicates.add(cb.equal(root.get("priority"), priority));
            }
            if (dueAfter != null) {
                predicates.add(cb.greaterThanOrEqualTo(root.get("dueDate"), dueAfter));
            }
            if (dueBefore != null) {
                predicates.add(cb.lessThanOrEqualTo(root.get("dueDate"), dueBefore));
            }
            if (search != null && !search.isBlank()) {
                String pattern = "%" + search.toLowerCase() + "%";
                predicates.add(cb.or(
                        cb.like(cb.lower(root.get("title").as(String.class)), pattern),
                        cb.like(cb.lower(cb.coalesce(root.get("description").as(String.class), "")), pattern)
                ));
            }
            return cb.and(predicates.toArray(Predicate[]::new));
        };
    }

    private boolean matchesTag(Todo todo, String tag) {
        if (tag == null || tag.isBlank()) return true;
        if (todo.getTags() == null) return false;
        String expected = tag.trim();
        return todo.getTags().stream().anyMatch(expected::equalsIgnoreCase);
    }

    private String normalizeSearch(String search) { return search == null || search.isBlank() ? null : search.trim(); }

    private Sort parseSort(String rawSort) {
        String value = rawSort == null || rawSort.isBlank() ? "created_at,desc" : rawSort.trim();
        String[] parts = value.split(",");
        String field = safeSort(parts[0]);
        Sort.Direction direction = parts.length > 1 && "asc".equalsIgnoreCase(parts[1]) ? Sort.Direction.ASC : Sort.Direction.DESC;
        return Sort.by(direction, field);
    }

    private String safeSort(String sort) {
        if (sort == null || sort.isBlank()) return "createdAt";
        return switch (sort) {
            case "title" -> "title";
            case "status" -> "status";
            case "priority" -> "priority";
            case "due_date", "dueDate" -> "dueDate";
            case "updated_at", "updatedAt" -> "updatedAt";
            case "created_at", "createdAt" -> "createdAt";
            default -> "createdAt";
        };
    }
}
