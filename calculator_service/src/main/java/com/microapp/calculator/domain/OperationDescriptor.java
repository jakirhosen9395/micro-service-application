package com.microapp.calculator.domain;

public record OperationDescriptor(
        String operation,
        String description,
        String arityDescription,
        int minOperands,
        int maxOperands
) {
    public static OperationDescriptor from(Operation operation) {
        return new OperationDescriptor(operation.name(), operation.description(), operation.arityDescription(), operation.minOperands(), operation.maxOperands());
    }
}
