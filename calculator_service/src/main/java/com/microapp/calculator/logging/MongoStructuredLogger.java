package com.microapp.calculator.logging;

import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.security.UserPrincipal;
import com.microapp.calculator.util.RequestContext;
import com.microapp.calculator.util.SecretRedactor;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoCollection;
import com.mongodb.client.model.Indexes;
import org.bson.Document;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.net.InetAddress;
import java.time.Instant;
import java.util.Map;

@Component
public class MongoStructuredLogger {
    private static final Logger log = LoggerFactory.getLogger(MongoStructuredLogger.class);
    private final AppProperties props;
    private final MongoClient mongoClient;
    private final String host;

    public MongoStructuredLogger(AppProperties props, MongoClient mongoClient) {
        this.props = props;
        this.mongoClient = mongoClient;
        this.host = resolveHost();
    }

    public void ensureIndexes() {
        try {
            MongoCollection<Document> collection = collection();
            collection.createIndex(Indexes.descending("timestamp"));
            collection.createIndex(Indexes.compoundIndex(Indexes.ascending("level"), Indexes.descending("timestamp")));
            collection.createIndex(Indexes.compoundIndex(Indexes.ascending("event"), Indexes.descending("timestamp")));
            collection.createIndex(Indexes.ascending("request_id"));
            collection.createIndex(Indexes.ascending("trace_id"));
            collection.createIndex(Indexes.compoundIndex(Indexes.ascending("user_id"), Indexes.descending("timestamp")));
            collection.createIndex(Indexes.compoundIndex(Indexes.ascending("path"), Indexes.ascending("status_code"), Indexes.descending("timestamp")));
            collection.createIndex(Indexes.compoundIndex(Indexes.ascending("error_code"), Indexes.descending("timestamp")));
            info("mongodb.indexes.ready", "MongoDB log indexes ready", Map.of("collection", props.getMongo().getLogCollection()));
        } catch (Exception ex) {
            log.warn("event=mongodb.indexes.failed message={}", SecretRedactor.redact(ex.getMessage()));
        }
    }

    public void info(String event, String message, Map<String, Object> extra) {
        write("INFO", event, message, null, null, extra);
    }

    public void warn(String event, String message, String errorCode, Map<String, Object> extra) {
        write("WARN", event, message, errorCode, null, extra);
    }

    public void error(String event, String message, String errorCode, Throwable throwable, Map<String, Object> extra) {
        write("ERROR", event, message, errorCode, throwable, extra);
    }

    public void request(String event, String message, String method, String path, Integer statusCode, double durationMs, String errorCode, Map<String, Object> extra) {
        Document doc = base("INFO", event, message, errorCode, null, extra);
        doc.put("logger", "app.request");
        doc.put("method", method);
        doc.put("path", path);
        doc.put("status_code", statusCode);
        doc.put("duration_ms", durationMs);
        insert(doc);
    }

    private void write(String level, String event, String message, String errorCode, Throwable throwable, Map<String, Object> extra) {
        insert(base(level, event, message, errorCode, throwable, extra));
    }

    private Document base(String level, String event, String message, String errorCode, Throwable throwable, Map<String, Object> extra) {
        RequestContext.Context ctx = RequestContext.current();
        UserPrincipal user = ctx.user();
        Document doc = new Document();
        doc.put("timestamp", Instant.now().toString());
        doc.put("level", level);
        doc.put("service", props.getServiceName());
        doc.put("version", props.getVersion());
        doc.put("environment", props.getEnvironment());
        doc.put("tenant", props.getTenant());
        doc.put("logger", "app.application");
        doc.put("event", event);
        doc.put("message", SecretRedactor.redact(message));
        doc.put("request_id", ctx.requestId());
        doc.put("trace_id", ctx.traceId());
        doc.put("correlation_id", ctx.correlationId());
        doc.put("user_id", user == null ? null : user.userId());
        doc.put("actor_id", user == null ? null : user.userId());
        doc.put("method", null);
        doc.put("path", null);
        doc.put("status_code", null);
        doc.put("duration_ms", null);
        doc.put("client_ip", ctx.clientIp());
        doc.put("user_agent", ctx.userAgent());
        doc.put("dependency", null);
        doc.put("error_code", errorCode);
        doc.put("exception_class", throwable == null ? null : throwable.getClass().getName());
        doc.put("exception_message", throwable == null ? null : SecretRedactor.redact(throwable.getMessage()));
        doc.put("stack_trace", throwable == null ? null : limitedStack(throwable));
        doc.put("host", host);
        doc.put("extra", new Document(sanitizeMap(extra)));
        return doc;
    }

    private void insert(Document doc) {
        try {
            collection().insertOne(doc);
        } catch (Exception ex) {
            log.warn("event=mongodb.log.write.failed message={}", SecretRedactor.redact(ex.getMessage()));
        }
    }

    private MongoCollection<Document> collection() {
        return mongoClient.getDatabase(props.getMongo().getDatabase()).getCollection(props.getMongo().getLogCollection());
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> sanitizeMap(Map<String, Object> extra) {
        Object sanitized = SecretRedactor.sanitize(extra == null ? Map.of() : extra);
        if (sanitized instanceof Map<?, ?> map) {
            return (Map<String, Object>) map;
        }
        return Map.of();
    }

    private static String limitedStack(Throwable throwable) {
        StringBuilder sb = new StringBuilder();
        StackTraceElement[] stack = throwable.getStackTrace();
        for (int i = 0; i < Math.min(12, stack.length); i++) {
            sb.append(stack[i]).append('\n');
        }
        return sb.toString();
    }

    private static String resolveHost() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (Exception ex) {
            return "unknown";
        }
    }
}
