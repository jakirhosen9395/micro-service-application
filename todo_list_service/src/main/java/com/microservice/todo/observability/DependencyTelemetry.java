package com.microservice.todo.observability;

import co.elastic.apm.api.ElasticApm;
import co.elastic.apm.api.Span;
import java.util.function.Supplier;
import org.springframework.stereotype.Component;

@Component
public class DependencyTelemetry {

    public <T> T capture(String name, String type, String subtype, String action, Supplier<T> supplier) {
        Span span = ElasticApm.currentSpan().startSpan(type, subtype, action);
        try {
            span.setName(name);
            span.setLabel("dependency", subtype == null ? type : subtype);
            span.setLabel("span_type", type == null ? "custom" : type);
            if (action != null && !action.isBlank()) {
                span.setLabel("span_action", action);
            }
            return supplier.get();
        } catch (RuntimeException ex) {
            span.captureException(ex);
            throw ex;
        } catch (Error err) {
            span.captureException(err);
            throw err;
        } finally {
            span.end();
        }
    }

    public void captureVoid(String name, String type, String subtype, String action, Runnable runnable) {
        capture(name, type, subtype, action, () -> {
            runnable.run();
            return null;
        });
    }
}
