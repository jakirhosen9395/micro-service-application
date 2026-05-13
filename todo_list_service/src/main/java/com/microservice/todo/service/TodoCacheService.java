package com.microservice.todo.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.microservice.todo.config.TodoProperties;
import com.microservice.todo.dto.TodoHistoryData;
import com.microservice.todo.dto.TodoPageData;
import com.microservice.todo.dto.TodoResponse;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.util.HexFormat;
import java.util.List;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

@Service
public class TodoCacheService {
    private static final Logger log = LoggerFactory.getLogger(TodoCacheService.class);
    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper;
    private final TodoProperties properties;

    public TodoCacheService(StringRedisTemplate redisTemplate, ObjectMapper objectMapper, TodoProperties properties) {
        this.redisTemplate = redisTemplate;
        this.objectMapper = objectMapper;
        this.properties = properties;
    }

    public Optional<TodoResponse> get(String tenant, String userId, String todoId) {
        try {
            String json = redisTemplate.opsForValue().get(recordKey(tenant, todoId));
            if (json == null || json.isBlank()) return Optional.empty();
            TodoResponse response = objectMapper.readValue(json, TodoResponse.class);
            if (!response.userId().equals(userId)) return Optional.empty();
            return Optional.of(response);
        } catch (Exception ex) {
            log.debug("event=redis.cache_get status=failed detail={}", ex.getMessage());
            return Optional.empty();
        }
    }

    public void put(TodoResponse response) {
        set(recordKey(response.tenant(), response.id()), response);
    }

    public Optional<TodoPageData> getPage(String key) {
        return read(key, TodoPageData.class);
    }

    public void putPage(String key, TodoPageData data) {
        set(key, data);
    }

    public Optional<List<TodoResponse>> getTodoList(String key) {
        try {
            String json = redisTemplate.opsForValue().get(key);
            if (json == null || json.isBlank()) return Optional.empty();
            return Optional.of(objectMapper.readValue(json, new TypeReference<List<TodoResponse>>() {}));
        } catch (Exception ex) {
            log.debug("event=redis.cache_list_get status=failed detail={}", ex.getMessage());
            return Optional.empty();
        }
    }

    public void putTodoList(String key, List<TodoResponse> data) {
        set(key, data);
    }

    public Optional<TodoHistoryData> getHistory(String tenant, String todoId) {
        return read(historyKey(tenant, todoId), TodoHistoryData.class);
    }

    public void putHistory(String tenant, String todoId, TodoHistoryData data) {
        set(historyKey(tenant, todoId), data);
    }

    public void evict(String tenant, String userId, String todoId) {
        try {
            redisTemplate.delete(recordKey(tenant, todoId));
            evictUserLists(tenant, userId);
            evictSpecialLists(tenant, userId);
            redisTemplate.delete(historyKey(tenant, todoId));
        } catch (Exception ex) {
            log.debug("event=redis.cache_evict status=failed detail={}", ex.getMessage());
        }
    }

    public String listKey(String tenant, String userId, Object... parts) {
        return prefix() + "list:" + tenant + ":" + userId + ":" + hash(parts);
    }

    public String todayKey(String tenant, String userId, int limit) {
        return prefix() + "today:" + tenant + ":" + userId + ":" + limit;
    }

    public String overdueKey(String tenant, String userId, int limit) {
        return prefix() + "overdue:" + tenant + ":" + userId + ":" + limit;
    }

    public void evictUserLists(String tenant, String userId) {
        try {
            var keys = redisTemplate.keys(prefix() + "list:" + tenant + ":" + userId + ":*");
            if (keys != null && !keys.isEmpty()) redisTemplate.delete(keys);
        } catch (Exception ex) {
            log.debug("event=redis.cache_list_evict status=failed detail={}", ex.getMessage());
        }
    }

    private void evictSpecialLists(String tenant, String userId) {
        var today = redisTemplate.keys(prefix() + "today:" + tenant + ":" + userId + ":*");
        if (today != null && !today.isEmpty()) redisTemplate.delete(today);
        var overdue = redisTemplate.keys(prefix() + "overdue:" + tenant + ":" + userId + ":*");
        if (overdue != null && !overdue.isEmpty()) redisTemplate.delete(overdue);
    }

    private <T> Optional<T> read(String key, Class<T> type) {
        try {
            String json = redisTemplate.opsForValue().get(key);
            if (json == null || json.isBlank()) return Optional.empty();
            return Optional.of(objectMapper.readValue(json, type));
        } catch (Exception ex) {
            log.debug("event=redis.cache_get status=failed detail={}", ex.getMessage());
            return Optional.empty();
        }
    }

    private void set(String key, Object value) {
        try {
            redisTemplate.opsForValue().set(key, objectMapper.writeValueAsString(value), Duration.ofSeconds(properties.getRedis().getCacheTtlSeconds()));
        } catch (Exception ex) {
            log.debug("event=redis.cache_set status=failed detail={}", ex.getMessage());
        }
    }

    private String recordKey(String tenant, String todoId) {
        return prefix() + "record:" + tenant + ":" + todoId;
    }

    private String historyKey(String tenant, String todoId) {
        return prefix() + "history:" + tenant + ":" + todoId;
    }

    private String prefix() {
        return displayEnvironment(properties.getEnv()) + ":" + properties.getServiceName() + ":";
    }

    private String displayEnvironment(String env) {
        return switch (env == null ? "" : env.toLowerCase()) {
            case "dev", "development" -> "development";
            case "stage", "staging" -> "stage";
            case "prod", "production" -> "production";
            default -> env;
        };
    }

    private String hash(Object... parts) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] bytes = digest.digest(objectMapper.writeValueAsString(parts).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(bytes).substring(0, 32);
        } catch (Exception ex) {
            return Integer.toHexString(java.util.Arrays.deepHashCode(parts));
        }
    }
}
