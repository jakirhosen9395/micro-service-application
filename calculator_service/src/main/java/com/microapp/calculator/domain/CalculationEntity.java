package com.microapp.calculator.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

public class CalculationEntity {
    private String id;
    private String tenant;
    private String userId;
    private String actorId;
    private String operation;
    private String expression;
    private List<BigDecimal> operands;
    private String result;
    private BigDecimal numericResult;
    private String status;
    private String errorCode;
    private String errorMessage;
    private String requestId;
    private String traceId;
    private String correlationId;
    private String clientIp;
    private String userAgent;
    private long durationMs;
    private String s3ObjectKey;
    private Instant createdAt;
    private Instant updatedAt;
    private Instant deletedAt;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getTenant() { return tenant; }
    public void setTenant(String tenant) { this.tenant = tenant; }
    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }
    public String getActorId() { return actorId; }
    public void setActorId(String actorId) { this.actorId = actorId; }
    public String getOperation() { return operation; }
    public void setOperation(String operation) { this.operation = operation; }
    public String getExpression() { return expression; }
    public void setExpression(String expression) { this.expression = expression; }
    public List<BigDecimal> getOperands() { return operands; }
    public void setOperands(List<BigDecimal> operands) { this.operands = operands; }
    public String getResult() { return result; }
    public void setResult(String result) { this.result = result; }
    public BigDecimal getNumericResult() { return numericResult; }
    public void setNumericResult(BigDecimal numericResult) { this.numericResult = numericResult; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public String getErrorCode() { return errorCode; }
    public void setErrorCode(String errorCode) { this.errorCode = errorCode; }
    public String getErrorMessage() { return errorMessage; }
    public void setErrorMessage(String errorMessage) { this.errorMessage = errorMessage; }
    public String getRequestId() { return requestId; }
    public void setRequestId(String requestId) { this.requestId = requestId; }
    public String getTraceId() { return traceId; }
    public void setTraceId(String traceId) { this.traceId = traceId; }
    public String getCorrelationId() { return correlationId; }
    public void setCorrelationId(String correlationId) { this.correlationId = correlationId; }
    public String getClientIp() { return clientIp; }
    public void setClientIp(String clientIp) { this.clientIp = clientIp; }
    public String getUserAgent() { return userAgent; }
    public void setUserAgent(String userAgent) { this.userAgent = userAgent; }
    public long getDurationMs() { return durationMs; }
    public void setDurationMs(long durationMs) { this.durationMs = durationMs; }
    public String getS3ObjectKey() { return s3ObjectKey; }
    public void setS3ObjectKey(String s3ObjectKey) { this.s3ObjectKey = s3ObjectKey; }
    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
    public Instant getDeletedAt() { return deletedAt; }
    public void setDeletedAt(Instant deletedAt) { this.deletedAt = deletedAt; }
}
