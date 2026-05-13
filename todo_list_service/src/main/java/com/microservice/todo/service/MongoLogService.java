package com.microservice.todo.service;

import com.microservice.todo.config.TodoProperties;
import com.microservice.todo.observability.ApmTraceContext;
import com.microservice.todo.util.RequestContext;
import com.microservice.todo.util.SecretRedactor;
import java.time.Instant;
import java.util.Map;
import org.bson.Document;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.stereotype.Service;

@Service
public class MongoLogService {
    private static final Logger log = LoggerFactory.getLogger(MongoLogService.class);
    private final MongoTemplate mongoTemplate;
    private final TodoProperties properties;

    public MongoLogService(MongoTemplate mongoTemplate, TodoProperties properties) {
        this.mongoTemplate = mongoTemplate;
        this.properties = properties;
    }

    public void log(String event, String todoId, String userId, Map<String, Object> data) {
        try {
            var metadata = RequestContext.metadata();
            ApmTraceContext.Ids apmIds = ApmTraceContext.current();
            Document document = new Document()
                    .append("timestamp", Instant.now().toString())
                    .append("level", "INFO")
                    .append("service", properties.getServiceName())
                    .append("version", properties.getServiceVersion())
                    .append("environment", displayEnvironment(properties.getEnv()))
                    .append("tenant", safeValue(MDC.get("tenant"), properties.getTenant()))
                    .append("logger", "app.domain")
                    .append("event", event)
                    .append("message", event)
                    .append("request_id", metadata.requestId())
                    .append("trace_id", metadata.traceId())
                    .append("correlation_id", metadata.correlationId())
                    .append("user_id", userId)
                    .append("actor_id", MDC.get("userId"))
                    .append("elastic_trace_id", apmIds.traceId())
                    .append("elastic_transaction_id", apmIds.transactionId())
                    .append("elastic_span_id", apmIds.spanId())
                    .append("method", MDC.get("method"))
                    .append("path", MDC.get("path"))
                    .append("status_code", parseInteger(MDC.get("statusCode")))
                    .append("duration_ms", parseLong(MDC.get("durationMs")))
                    .append("client_ip", metadata.clientIp())
                    .append("user_agent", metadata.userAgent())
                    .append("dependency", null)
                    .append("error_code", null)
                    .append("exception_class", null)
                    .append("exception_message", null)
                    .append("stack_trace", null)
                    .append("host", System.getenv().getOrDefault("HOSTNAME", "local"))
                    .append("extra", new Document("todo_id", todoId).append("data", SecretRedactor.redactMap(data == null ? Map.of() : data)));
            mongoTemplate.getCollection(properties.getMongo().getLogCollection()).insertOne(document);
        } catch (Exception ex) {
            log.debug("event=mongodb.log_write.failed detail={}", ex.getMessage());
        }
    }

    private String safeValue(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }

    private String displayEnvironment(String env) {
        return switch (env == null ? "" : env.toLowerCase()) {
            case "dev", "development" -> "development";
            case "stage", "staging" -> "stage";
            case "prod", "production" -> "production";
            default -> env;
        };
    }

    private Integer parseInteger(String value) {
        try { return value == null ? null : Integer.parseInt(value); }
        catch (NumberFormatException ex) { return null; }
    }

    private Long parseLong(String value) {
        try { return value == null ? null : Long.parseLong(value); }
        catch (NumberFormatException ex) { return null; }
    }
}
