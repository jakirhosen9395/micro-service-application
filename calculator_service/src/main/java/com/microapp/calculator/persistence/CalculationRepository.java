package com.microapp.calculator.persistence;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.domain.CalculationEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

@Repository
public class CalculationRepository {
    private static final TypeReference<List<BigDecimal>> OPERANDS_TYPE = new TypeReference<>() {};
    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;
    private final String calculationsTable;

    public CalculationRepository(JdbcTemplate jdbc, ObjectMapper mapper, AppProperties props) {
        this.jdbc = jdbc;
        this.mapper = mapper;
        this.calculationsTable = qualifiedTable(props, "calculations");
    }

    public void insert(CalculationEntity entity) {
        String sql = """
                INSERT INTO %s (
                  id, tenant, user_id, actor_id, operation, expression, operands, result, numeric_result,
                  status, error_code, error_message, request_id, trace_id, correlation_id, client_ip, user_agent, duration_ms
                ) VALUES (?, ?, ?, ?, ?, ?, CAST(? AS jsonb), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """.formatted(calculationsTable);
        jdbc.update(sql,
                entity.getId(), entity.getTenant(), entity.getUserId(), entity.getActorId(), entity.getOperation(), entity.getExpression(), writeOperands(entity.getOperands()), entity.getResult(), entity.getNumericResult(),
                entity.getStatus(), entity.getErrorCode(), entity.getErrorMessage(), entity.getRequestId(), entity.getTraceId(), entity.getCorrelationId(), entity.getClientIp(), entity.getUserAgent(), entity.getDurationMs());
    }

    public void updateS3ObjectKey(String id, String tenant, String s3ObjectKey) {
        jdbc.update("UPDATE %s SET s3_object_key = ?, updated_at = now() WHERE id = ? AND tenant = ?".formatted(calculationsTable), s3ObjectKey, id, tenant);
    }

    public Optional<CalculationEntity> findById(String tenant, String id) {
        List<CalculationEntity> rows = jdbc.query("SELECT * FROM %s WHERE tenant = ? AND id = ? AND deleted_at IS NULL".formatted(calculationsTable), mapper(), tenant, id);
        return rows.stream().findFirst();
    }

    public List<CalculationEntity> findHistory(String tenant, String userId, int limit) {
        return jdbc.query("""
                SELECT * FROM %s
                WHERE tenant = ? AND user_id = ? AND deleted_at IS NULL
                ORDER BY created_at DESC
                LIMIT ?
                """.formatted(calculationsTable), mapper(), tenant, userId, limit);
    }

    public int softDeleteHistory(String tenant, String userId) {
        return jdbc.update("""
                UPDATE %s
                SET deleted_at = now(), updated_at = now()
                WHERE tenant = ? AND user_id = ? AND deleted_at IS NULL
                """.formatted(calculationsTable), tenant, userId);
    }

    private RowMapper<CalculationEntity> mapper() {
        return (rs, rowNum) -> {
            CalculationEntity entity = new CalculationEntity();
            entity.setId(rs.getString("id"));
            entity.setTenant(rs.getString("tenant"));
            entity.setUserId(rs.getString("user_id"));
            entity.setActorId(rs.getString("actor_id"));
            entity.setOperation(rs.getString("operation"));
            entity.setExpression(rs.getString("expression"));
            entity.setOperands(readOperands(rs));
            entity.setResult(rs.getString("result"));
            entity.setNumericResult(rs.getBigDecimal("numeric_result"));
            entity.setStatus(rs.getString("status"));
            entity.setErrorCode(rs.getString("error_code"));
            entity.setErrorMessage(rs.getString("error_message"));
            entity.setRequestId(rs.getString("request_id"));
            entity.setTraceId(rs.getString("trace_id"));
            entity.setCorrelationId(rs.getString("correlation_id"));
            entity.setClientIp(rs.getString("client_ip"));
            entity.setUserAgent(rs.getString("user_agent"));
            entity.setDurationMs(rs.getLong("duration_ms"));
            entity.setS3ObjectKey(rs.getString("s3_object_key"));
            entity.setCreatedAt(instant(rs, "created_at"));
            entity.setUpdatedAt(instant(rs, "updated_at"));
            entity.setDeletedAt(instant(rs, "deleted_at"));
            return entity;
        };
    }

    private List<BigDecimal> readOperands(ResultSet rs) {
        try {
            String json = rs.getString("operands");
            if (json == null || json.isBlank()) {
                return List.of();
            }
            return mapper.readValue(json, OPERANDS_TYPE);
        } catch (Exception ex) {
            return List.of();
        }
    }

    private String writeOperands(List<BigDecimal> operands) {
        try {
            return mapper.writeValueAsString(operands == null ? List.of() : operands);
        } catch (Exception ex) {
            return "[]";
        }
    }

    private static String qualifiedTable(AppProperties props, String tableName) {
        String schema = props.getPostgres().getSchema();
        if (schema == null || !schema.matches("[A-Za-z_][A-Za-z0-9_]*")) {
            throw new IllegalStateException("Invalid PostgreSQL schema name for calculator service");
        }
        return schema + "." + tableName;
    }

    private static Instant instant(ResultSet rs, String column) throws java.sql.SQLException {
        Timestamp ts = rs.getTimestamp(column);
        return ts == null ? null : ts.toInstant();
    }
}
