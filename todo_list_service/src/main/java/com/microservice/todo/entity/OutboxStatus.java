package com.microservice.todo.entity;

public enum OutboxStatus {
    PENDING,
    PROCESSING,
    SENT,
    FAILED,
    DEAD_LETTERED
}
