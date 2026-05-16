package com.microservice.todo.logging;

import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.AppenderBase;
import com.mongodb.ConnectionString;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import com.mongodb.client.MongoCollection;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.time.Instant;
import com.microservice.todo.observability.ApmTraceContext;
import com.microservice.todo.util.SecretRedactor;
import java.util.LinkedHashMap;
import java.util.Map;
import org.bson.Document;

public class MongoLogbackAppender extends AppenderBase<ILoggingEvent> {
    private boolean enabled = false;
    private String host = "localhost";
    private int port = 27017;
    private String username = "";
    private String password = "";
    private String database = "db_micro_services";
    private String authSource = "admin";
    private String collection = "todo_list_service_development_logs";
    private String service = "todo_list_service";
    private String version = "v1.0.0";
    private String environment = "development";

    private MongoClient mongoClient;
    private MongoCollection<Document> mongoCollection;

    @Override
    public void start() {
        if (!enabled) {
            super.start();
            return;
        }
        try {
            String uri = buildUri();
            mongoClient = MongoClients.create(new ConnectionString(uri));
            mongoCollection = mongoClient.getDatabase(database).getCollection(collection);
            super.start();
        } catch (Throwable ex) {
            addWarn("MongoLogbackAppender disabled: " + safeMessage(ex));
            enabled = false;
            super.start();
        }
    }

    @Override
    protected void append(ILoggingEvent eventObject) {
        if (!enabled || mongoCollection == null) return;
        try {
            Map<String, String> mdc = eventObject.getMDCPropertyMap();
            ApmTraceContext.Ids apmIds = ApmTraceContext.current();
            Document document = new Document()
                    .append("timestamp", Instant.ofEpochMilli(eventObject.getTimeStamp()).toString())
                    .append("level", eventObject.getLevel().toString())
                    .append("service", service)
                    .append("version", version)
                    .append("environment", environment)
                    .append("tenant", mdc.getOrDefault("tenant", "default"))
                    .append("logger", eventObject.getLoggerName())
                    .append("event", extractEvent(eventObject.getFormattedMessage()))
                    .append("message", SecretRedactor.redact(eventObject.getFormattedMessage()))
                    .append("request_id", mdc.get("requestId"))
                    .append("trace_id", mdc.get("traceId"))
                    .append("correlation_id", mdc.get("correlationId"))
                    .append("user_id", mdc.get("userId"))
                    .append("actor_id", mdc.get("userId"))
                    .append("elastic_trace_id", apmIds.traceId())
                    .append("elastic_transaction_id", apmIds.transactionId())
                    .append("elastic_span_id", apmIds.spanId())
                    .append("method", mdc.get("method"))
                    .append("path", mdc.get("path"))
                    .append("status_code", parseInteger(mdc.get("statusCode")))
                    .append("duration_ms", parseLong(mdc.get("durationMs")))
                    .append("client_ip", mdc.get("clientIp"))
                    .append("user_agent", mdc.get("userAgent"))
                    .append("dependency", null)
                    .append("error_code", null)
                    .append("exception_class", eventObject.getThrowableProxy() == null ? null : eventObject.getThrowableProxy().getClassName())
                    .append("exception_message", eventObject.getThrowableProxy() == null ? null : SecretRedactor.redact(eventObject.getThrowableProxy().getMessage()))
                    .append("stack_trace", SecretRedactor.redact(throwable(eventObject)))
                    .append("host", System.getenv().getOrDefault("HOSTNAME", "local"))
                    .append("extra", SecretRedactor.redactMap(mdcExtra(mdc)));
            mongoCollection.insertOne(document);
        } catch (Throwable ignored) {
            // Never let Mongo logging break application logging or request processing.
        }
    }

    @Override
    public void stop() {
        if (mongoClient != null) mongoClient.close();
        super.stop();
    }

    private String buildUri() {
        if (username == null || username.isBlank()) return "mongodb://" + host + ":" + port + "/" + database;
        return "mongodb://" + encode(username) + ":" + encode(password) + "@" + host + ":" + port + "/" + database + "?authSource=" + authSource;
    }

    private String encode(String value) {
        return value == null ? "" : value.replace("@", "%40").replace(":", "%3A").replace("/", "%2F");
    }

    private String safeMessage(Throwable ex) {
        String message = ex.getMessage();
        return (message == null || message.isBlank() ? ex.getClass().getSimpleName() : message).replaceAll("[\r\n]+", " ");
    }

    private Map<String, Object> mdcExtra(Map<String, String> mdc) {
        Map<String, Object> extra = new LinkedHashMap<>();
        if (mdc != null) extra.putAll(mdc);
        return extra;
    }

    private String extractEvent(String message) {
        if (message == null) return null;
        int idx = message.indexOf("event=");
        if (idx < 0) return null;
        String rest = message.substring(idx + 6);
        int end = rest.indexOf(' ');
        return end < 0 ? rest : rest.substring(0, end);
    }

    private Integer parseInteger(String value) {
        try { return value == null ? null : Integer.parseInt(value); } catch (NumberFormatException ex) { return null; }
    }

    private Long parseLong(String value) {
        try { return value == null ? null : Long.parseLong(value); } catch (NumberFormatException ex) { return null; }
    }

    private String throwable(ILoggingEvent eventObject) {
        if (eventObject.getThrowableProxy() == null) return null;
        StringWriter writer = new StringWriter();
        PrintWriter printWriter = new PrintWriter(writer);
        printWriter.println(eventObject.getThrowableProxy().getClassName() + ": " + eventObject.getThrowableProxy().getMessage());
        return writer.toString();
    }

    public void setEnabled(boolean enabled) { this.enabled = enabled; }
    public void setHost(String host) { this.host = host; }
    public void setPort(int port) { this.port = port; }
    public void setUsername(String username) { this.username = username; }
    public void setPassword(String password) { this.password = password; }
    public void setDatabase(String database) { this.database = database; }
    public void setAuthSource(String authSource) { this.authSource = authSource; }
    public void setCollection(String collection) { this.collection = collection; }
    public void setService(String service) { this.service = service; }
    public void setVersion(String version) { this.version = version; }
    public void setEnvironment(String environment) { this.environment = environment; }
}
