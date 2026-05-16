package com.microapp.calculator.observability;

import co.elastic.apm.api.ElasticApm;
import co.elastic.apm.api.Span;
import org.springframework.stereotype.Component;

/**
 * Small wrapper around the Elastic APM public API. The Java agent still auto-
 * instruments Spring MVC, JDBC, Kafka, Redis, MongoDB, and HTTP clients where
 * supported, but these manual spans make health/startup/dependency probes
 * visible in Kibana's APM dependency view even when a dependency is touched by
 * short custom code rather than by an auto-instrumented framework call.
 */
@Component
public class DependencyTelemetry {

    public <T> T capture(String type, String subtype, String action, String name, ThrowingSupplier<T> supplier) throws Exception {
        Span span = null;
        try {
            span = ElasticApm.currentSpan().startSpan(type, subtype, action);
            span.setName(name);
            span.setLabel("dependency.type", type);
            span.setLabel("dependency.subtype", subtype);
            span.setLabel("dependency.action", action);
            return supplier.get();
        } catch (Exception ex) {
            if (span != null) {
                span.captureException(ex);
            }
            throw ex;
        } finally {
            if (span != null) {
                span.end();
            }
        }
    }

    public void capture(String type, String subtype, String action, String name, ThrowingRunnable runnable) throws Exception {
        capture(type, subtype, action, name, () -> {
            runnable.run();
            return null;
        });
    }

    @FunctionalInterface
    public interface ThrowingSupplier<T> {
        T get() throws Exception;
    }

    @FunctionalInterface
    public interface ThrowingRunnable {
        void run() throws Exception;
    }
}
