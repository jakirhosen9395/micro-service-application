package com.microapp.calculator.logging;

import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.classic.spi.IThrowableProxy;
import ch.qos.logback.classic.spi.StackTraceElementProxy;
import ch.qos.logback.core.UnsynchronizedAppenderBase;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.microapp.calculator.util.SecretRedactor;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

public class PrettyJsonConsoleAppender extends UnsynchronizedAppenderBase<ILoggingEvent> {
    private final ObjectMapper mapper = new ObjectMapper()
            .registerModule(new JavaTimeModule())
            .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
            .enable(SerializationFeature.INDENT_OUTPUT);

    @Override
    protected void append(ILoggingEvent event) {
        try {
            Map<String, Object> json = new LinkedHashMap<>();
            json.put("timestamp", Instant.ofEpochMilli(event.getTimeStamp()).toString());
            json.put("level", event.getLevel().toString());
            json.put("logger", event.getLoggerName());
            json.put("thread", event.getThreadName());
            json.put("message", SecretRedactor.redact(event.getFormattedMessage()));
            putIfPresent(json, "request_id", event.getMDCPropertyMap().get("request_id"));
            putIfPresent(json, "trace_id", event.getMDCPropertyMap().get("trace_id"));
            putIfPresent(json, "correlation_id", event.getMDCPropertyMap().get("correlation_id"));
            putIfPresent(json, "user_id", event.getMDCPropertyMap().get("user_id"));
            putIfPresent(json, "actor_id", event.getMDCPropertyMap().get("actor_id"));
            IThrowableProxy throwable = event.getThrowableProxy();
            if (throwable != null) {
                json.put("exception_class", throwable.getClassName());
                json.put("exception_message", SecretRedactor.redact(throwable.getMessage()));
                json.put("stack_trace", limitedStackTrace(throwable));
            }
            System.out.println(mapper.writerWithDefaultPrettyPrinter().writeValueAsString(json));
        } catch (Exception ex) {
            System.out.println("{\"level\":\"ERROR\",\"message\":\"pretty json logging failed\"}");
        }
    }

    private static void putIfPresent(Map<String, Object> json, String key, String value) {
        if (value != null && !value.isBlank()) {
            json.put(key, value);
        }
    }

    private static String limitedStackTrace(IThrowableProxy throwable) {
        StackTraceElementProxy[] stack = throwable.getStackTraceElementProxyArray();
        if (stack == null || stack.length == 0) {
            return null;
        }
        StringBuilder builder = new StringBuilder();
        int max = Math.min(stack.length, 12);
        for (int i = 0; i < max; i++) {
            builder.append(stack[i].getSTEAsString()).append('\n');
        }
        return builder.toString();
    }
}
