package com.microservice.todo.observability;

import co.elastic.apm.api.ElasticApm;
import co.elastic.apm.api.Span;
import co.elastic.apm.api.Transaction;
import org.slf4j.MDC;

public final class ApmTraceContext {
    private ApmTraceContext() {
    }

    public static Ids current() {
        try {
            Span span = ElasticApm.currentSpan();
            Transaction transaction = ElasticApm.currentTransaction();
            return new Ids(blankToNull(span.getTraceId()), blankToNull(transaction.getId()), blankToNull(span.getId()));
        } catch (Throwable ignored) {
            return Ids.EMPTY;
        }
    }

    public static void putMdc() {
        Ids ids = current();
        put("elastic_trace_id", ids.traceId());
        put("elastic_transaction_id", ids.transactionId());
        put("elastic_span_id", ids.spanId());
        put("trace.id", ids.traceId());
        put("transaction.id", ids.transactionId());
        put("span.id", ids.spanId());
    }

    private static void put(String key, String value) {
        if (value != null && !value.isBlank()) {
            MDC.put(key, value);
        }
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }

    public record Ids(String traceId, String transactionId, String spanId) {
        private static final Ids EMPTY = new Ids(null, null, null);
    }
}
