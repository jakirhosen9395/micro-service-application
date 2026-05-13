package com.microapp.calculator.redis;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.domain.CalculationEntity;
import com.microapp.calculator.domain.HistoryView;
import com.microapp.calculator.util.SecretRedactor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.Optional;

@Service
public class CalculationCache {
    private static final Logger log = LoggerFactory.getLogger(CalculationCache.class);
    private final StringRedisTemplate redis;
    private final ObjectMapper mapper;
    private final AppProperties props;
    private final Duration ttl;

    public CalculationCache(StringRedisTemplate redis, ObjectMapper mapper, AppProperties props) {
        this.redis = redis;
        this.mapper = mapper;
        this.props = props;
        this.ttl = Duration.ofSeconds(props.getRedisCacheTtlSeconds());
    }

    public Optional<CalculationEntity> getRecord(String id) {
        try {
            String json = redis.opsForValue().get(recordKey(id));
            if (json == null || json.isBlank()) {
                return Optional.empty();
            }
            return Optional.of(mapper.readValue(json, CalculationEntity.class));
        } catch (Exception ex) {
            log.warn("event=redis.record.get.failed message={}", SecretRedactor.redact(ex.getMessage()));
            return Optional.empty();
        }
    }

    public void putRecord(CalculationEntity entity) {
        try {
            redis.opsForValue().set(recordKey(entity.getId()), mapper.writeValueAsString(entity), ttl);
        } catch (Exception ex) {
            log.warn("event=redis.record.put.failed calculation_id={} message={}", entity.getId(), SecretRedactor.redact(ex.getMessage()));
        }
    }

    public Optional<HistoryView> getHistory(String tenant, String userId, int limit) {
        try {
            String json = redis.opsForValue().get(historyKey(tenant, userId, limit));
            if (json == null || json.isBlank()) {
                return Optional.empty();
            }
            return Optional.of(mapper.readValue(json, new TypeReference<HistoryView>() {}));
        } catch (Exception ex) {
            log.warn("event=redis.history.get.failed message={}", SecretRedactor.redact(ex.getMessage()));
            return Optional.empty();
        }
    }

    public void putHistory(String tenant, String userId, int limit, HistoryView history) {
        try {
            redis.opsForValue().set(historyKey(tenant, userId, limit), mapper.writeValueAsString(history), ttl);
        } catch (Exception ex) {
            log.warn("event=redis.history.put.failed message={}", SecretRedactor.redact(ex.getMessage()));
        }
    }

    public void evictRecord(String id) {
        try {
            redis.delete(recordKey(id));
        } catch (Exception ex) {
            log.warn("event=redis.record.evict.failed message={}", SecretRedactor.redact(ex.getMessage()));
        }
    }

    public void evictHistory(String tenant, String userId) {
        try {
            String prefix = namespace() + "history:" + tenant + ":" + userId + ":";
            redis.delete(redis.keys(prefix + "*"));
        } catch (Exception ex) {
            log.warn("event=redis.history.evict.failed message={}", SecretRedactor.redact(ex.getMessage()));
        }
    }

    private String recordKey(String id) {
        return namespace() + "record:" + id;
    }

    private String historyKey(String tenant, String userId, int limit) {
        return namespace() + "history:" + tenant + ":" + userId + ":" + limit;
    }

    private String namespace() {
        return props.getEnvironment() + ":" + props.getServiceName() + ":";
    }
}
