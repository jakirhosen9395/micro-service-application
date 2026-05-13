package com.microservice.todo.service;

public record S3AuditResult(boolean written, String objectKey, String errorCode) {
    public static S3AuditResult written(String objectKey) {
        return new S3AuditResult(true, objectKey, null);
    }

    public static S3AuditResult failed(String errorCode) {
        return new S3AuditResult(false, null, errorCode);
    }
}
