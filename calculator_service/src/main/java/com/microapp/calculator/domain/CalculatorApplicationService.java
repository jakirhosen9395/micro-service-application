package com.microapp.calculator.domain;

import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.exception.ApiException;
import com.microapp.calculator.kafka.EventEnvelope;
import com.microapp.calculator.kafka.EventFactory;
import com.microapp.calculator.kafka.OutboxService;
import com.microapp.calculator.persistence.CalculationRepository;
import com.microapp.calculator.redis.CalculationCache;
import com.microapp.calculator.s3.S3AuditService;
import com.microapp.calculator.security.UserPrincipal;
import com.microapp.calculator.util.RequestContext;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

@Service
public class CalculatorApplicationService {
    private final AppProperties props;
    private final CalculatorEngine engine;
    private final CalculationRepository repository;
    private final CalculationCache cache;
    private final PermissionService permissions;
    private final EventFactory eventFactory;
    private final OutboxService outbox;
    private final S3AuditService s3AuditService;
    private final TransactionTemplate transactionTemplate;

    public CalculatorApplicationService(AppProperties props,
                                        CalculatorEngine engine,
                                        CalculationRepository repository,
                                        CalculationCache cache,
                                        PermissionService permissions,
                                        EventFactory eventFactory,
                                        OutboxService outbox,
                                        S3AuditService s3AuditService,
                                        TransactionTemplate transactionTemplate) {
        this.props = props;
        this.engine = engine;
        this.repository = repository;
        this.cache = cache;
        this.permissions = permissions;
        this.eventFactory = eventFactory;
        this.outbox = outbox;
        this.s3AuditService = s3AuditService;
        this.transactionTemplate = transactionTemplate;
    }

    public List<OperationDescriptor> operations() {
        return Arrays.stream(Operation.values()).map(OperationDescriptor::from).toList();
    }

    public CalculationView calculate(CalculationRequest request) {
        UserPrincipal user = RequestContext.user();
        long start = System.nanoTime();
        CalculationEntity entity;
        EventEnvelope event;
        try {
            validateCalculateRequest(request);
            BigDecimal result = request.expression() != null && !request.expression().isBlank()
                    ? engine.evaluateExpression(request.expression())
                    : engine.evaluateOperation(request.operation(), request.operands());
            entity = createEntity(user, request, result, "COMPLETED", null, null, elapsedMs(start));
            event = eventFactory.createForUser("calculation.completed", user, "calculation", entity.getId(), eventPayload(entity));
            final CalculationEntity completedEntity = entity;
            final EventEnvelope completedEvent = event;
            transactionTemplate.executeWithoutResult(status -> {
                repository.insert(completedEntity);
                outbox.enqueue(completedEvent);
            });
        } catch (ApiException ex) {
            entity = createEntity(user, request, null, "FAILED", ex.errorCode(), ex.getMessage(), elapsedMs(start));
            event = eventFactory.createForUser("calculation.failed", user, "calculation", entity.getId(), eventPayload(entity));
            final CalculationEntity failedEntity = entity;
            final EventEnvelope failedEvent = event;
            transactionTemplate.executeWithoutResult(status -> {
                repository.insert(failedEntity);
                outbox.enqueue(failedEvent);
            });
            writeAuditAndUpdate(entity, event, null);
            cache.evictHistory(entity.getTenant(), entity.getUserId());
            throw ex;
        }
        writeAuditAndUpdate(entity, event, null);
        cache.putRecord(entity);
        cache.evictHistory(entity.getTenant(), entity.getUserId());
        return CalculationView.from(entity);
    }

    public HistoryView historyForCurrentUser(int requestedLimit) {
        UserPrincipal user = RequestContext.user();
        return history(user.userId(), requestedLimit);
    }

    public HistoryView history(String targetUserId, int requestedLimit) {
        UserPrincipal user = RequestContext.user();
        permissions.requireCanReadUser(user, targetUserId);
        int limit = normalizeLimit(requestedLimit);
        return cache.getHistory(user.tenant(), targetUserId, limit).orElseGet(() -> {
            List<CalculationView> items = repository.findHistory(user.tenant(), targetUserId, limit).stream().map(CalculationView::from).toList();
            HistoryView view = new HistoryView(targetUserId, limit, items.size(), items, "postgres");
            cache.putHistory(user.tenant(), targetUserId, limit, view);
            return view;
        });
    }

    public CalculationView record(String calculationId) {
        UserPrincipal user = RequestContext.user();
        CalculationEntity entity = cache.getRecord(calculationId)
                .filter(c -> c.getTenant().equals(user.tenant()) && c.getDeletedAt() == null)
                .orElseGet(() -> repository.findById(user.tenant(), calculationId)
                        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "CALC_RECORD_NOT_FOUND", "Calculation record not found")));
        permissions.requireCanReadUser(user, entity.getUserId());
        cache.putRecord(entity);
        return CalculationView.from(entity);
    }

    public Map<String, Object> clearHistory() {
        UserPrincipal user = RequestContext.user();
        String aggregateId = "history-" + user.userId() + "-" + UUID.randomUUID();
        AtomicReference<EventEnvelope> eventRef = new AtomicReference<>();
        Integer deleted = transactionTemplate.execute(status -> {
            int count = repository.softDeleteHistory(user.tenant(), user.userId());
            EventEnvelope event = eventFactory.createForUser("calculation.history.cleared", user, "calculation_history", aggregateId, Map.of("deleted_count", count));
            outbox.enqueue(event);
            eventRef.set(event);
            return count;
        });
        if (eventRef.get() != null) {
            writeAuditAfterTransaction(eventRef.get(), null);
        }
        cache.evictHistory(user.tenant(), user.userId());
        return Map.of("deleted_count", deleted == null ? 0 : deleted);
    }

    private void writeAuditAndUpdate(CalculationEntity entity, EventEnvelope event, String targetUserId) {
        String key = s3AuditService.writeAuditSnapshot(event, targetUserId);
        if (key != null) {
            entity.setS3ObjectKey(key);
            transactionTemplate.executeWithoutResult(status -> repository.updateS3ObjectKey(entity.getId(), entity.getTenant(), key));
            EventEnvelope auditEvent = eventFactory.create("calculation.audit.s3_written",
                    entity.getUserId(), entity.getActorId(), "calculation", entity.getId(), Map.of("s3_object_key", key, "source_event_type", event.eventType()));
            transactionTemplate.executeWithoutResult(status -> outbox.enqueue(auditEvent));
        } else {
            EventEnvelope auditEvent = eventFactory.create("calculation.audit.s3_failed",
                    entity.getUserId(), entity.getActorId(), "calculation", entity.getId(), Map.of("source_event_type", event.eventType()));
            transactionTemplate.executeWithoutResult(status -> outbox.enqueue(auditEvent));
        }
    }

    private void writeAuditAfterTransaction(EventEnvelope event, String targetUserId) {
        // This method intentionally performs S3 after the transactional state has been queued.
        // It is small and safe to call from existing service flows; failures publish a later audit-failed event.
        String key = s3AuditService.writeAuditSnapshot(event, targetUserId);
        EventEnvelope auditEvent = eventFactory.create(key == null ? "calculation.audit.s3_failed" : "calculation.audit.s3_written",
                event.userId(), event.actorId(), event.aggregateType(), event.aggregateId(),
                key == null ? Map.of("source_event_type", event.eventType()) : Map.of("s3_object_key", key, "source_event_type", event.eventType()));
        transactionTemplate.executeWithoutResult(status -> outbox.enqueue(auditEvent));
    }

    private CalculationEntity createEntity(UserPrincipal user, CalculationRequest request, BigDecimal result, String status, String errorCode, String errorMessage, long durationMs) {
        CalculationEntity entity = new CalculationEntity();
        entity.setId("calc-" + UUID.randomUUID());
        entity.setTenant(user.tenant());
        entity.setUserId(user.userId());
        entity.setActorId(user.userId());
        entity.setOperation(request == null ? null : normalizeOperation(request.operation()));
        entity.setExpression(request == null ? null : trimToNull(request.expression()));
        entity.setOperands(request == null || request.operands() == null ? List.of() : request.operands());
        entity.setResult(result == null ? null : result.toPlainString());
        entity.setNumericResult(result);
        entity.setStatus(status);
        entity.setErrorCode(errorCode);
        entity.setErrorMessage(errorMessage);
        entity.setRequestId(RequestContext.requestId());
        entity.setTraceId(RequestContext.traceId());
        entity.setCorrelationId(RequestContext.correlationId());
        entity.setClientIp(RequestContext.clientIp());
        entity.setUserAgent(RequestContext.userAgent());
        entity.setDurationMs(durationMs);
        entity.setCreatedAt(Instant.now());
        entity.setUpdatedAt(Instant.now());
        return entity;
    }

    private Map<String, Object> eventPayload(CalculationEntity entity) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("calculation_id", entity.getId());
        payload.put("operation", entity.getOperation());
        payload.put("expression", entity.getExpression());
        payload.put("operands", entity.getOperands());
        payload.put("result", entity.getResult());
        payload.put("status", entity.getStatus());
        payload.put("error_code", entity.getErrorCode());
        payload.put("duration_ms", entity.getDurationMs());
        payload.put("created_at", entity.getCreatedAt() == null ? Instant.now().toString() : entity.getCreatedAt().toString());
        return payload;
    }

    private void validateCalculateRequest(CalculationRequest request) {
        if (request == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "CALC_REQUEST_REQUIRED", "Request body is required");
        }
        boolean hasExpression = request.expression() != null && !request.expression().isBlank();
        boolean hasOperation = request.operation() != null && !request.operation().isBlank();
        if (hasExpression == hasOperation) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "CALC_MODE_INVALID", "Provide exactly one of expression or operation");
        }
        if (hasExpression && request.expression().length() > props.getMaxExpressionLength()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "CALC_EXPRESSION_TOO_LONG", "Expression exceeds maximum length");
        }
        if (hasOperation && (request.operands() == null || request.operands().isEmpty())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "CALC_OPERANDS_REQUIRED", "operands are required for operation mode");
        }
    }

    private int normalizeLimit(int requestedLimit) {
        if (requestedLimit <= 0) {
            return props.getHistoryDefaultLimit();
        }
        return Math.min(requestedLimit, props.getHistoryMaxLimit());
    }

    private static String normalizeOperation(String operation) {
        return operation == null || operation.isBlank() ? null : operation.trim().toUpperCase();
    }

    private static String trimToNull(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }

    private static long elapsedMs(long start) {
        return Math.max(0L, (System.nanoTime() - start) / 1_000_000L);
    }
}
