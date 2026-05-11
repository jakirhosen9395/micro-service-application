package com.microapp.calculator.kafka;

import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.security.UserPrincipal;
import com.microapp.calculator.util.RequestContext;
import com.microapp.calculator.util.SecretRedactor;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

@Component
public class EventFactory {
    private final AppProperties props;

    public EventFactory(AppProperties props) {
        this.props = props;
    }

    @SuppressWarnings("unchecked")
    public EventEnvelope create(String eventType, String userId, String actorId, String aggregateType, String aggregateId, Map<String, Object> payload) {
        RequestContext.Context ctx = RequestContext.current();
        Object sanitized = SecretRedactor.sanitize(payload == null ? Map.of() : payload);
        return new EventEnvelope(
                "evt-" + UUID.randomUUID(),
                eventType,
                "1.0",
                props.getServiceName(),
                props.getEnvironment(),
                props.getTenant(),
                Instant.now(),
                ctx.requestId(),
                ctx.traceId(),
                ctx.correlationId(),
                userId,
                actorId,
                aggregateType,
                aggregateId,
                sanitized instanceof Map<?, ?> m ? (Map<String, Object>) m : Map.of()
        );
    }

    public EventEnvelope createForUser(String eventType, UserPrincipal user, String aggregateType, String aggregateId, Map<String, Object> payload) {
        return create(eventType, user.userId(), user.userId(), aggregateType, aggregateId, payload);
    }
}
