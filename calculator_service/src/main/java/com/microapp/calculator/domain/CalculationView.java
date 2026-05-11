package com.microapp.calculator.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

public record CalculationView(
        String calculationId,
        String userId,
        String tenant,
        String operation,
        String expression,
        List<BigDecimal> operands,
        String result,
        String status,
        String errorCode,
        String errorMessage,
        long durationMs,
        String s3ObjectKey,
        Instant createdAt
) {
    public static CalculationView from(CalculationEntity entity) {
        return new CalculationView(
                entity.getId(),
                entity.getUserId(),
                entity.getTenant(),
                entity.getOperation(),
                entity.getExpression(),
                entity.getOperands(),
                entity.getResult(),
                entity.getStatus(),
                entity.getErrorCode(),
                entity.getErrorMessage(),
                entity.getDurationMs(),
                entity.getS3ObjectKey(),
                entity.getCreatedAt()
        );
    }
}
