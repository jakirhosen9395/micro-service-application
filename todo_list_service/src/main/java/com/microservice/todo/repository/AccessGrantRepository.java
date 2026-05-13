package com.microservice.todo.repository;

import com.microservice.todo.config.TodoProperties;
import java.time.Instant;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class AccessGrantRepository {
    private final JdbcTemplate jdbc;
    private final String tableName;

    public AccessGrantRepository(JdbcTemplate jdbc, TodoProperties properties) {
        this.jdbc = jdbc;
        this.tableName = qualifiedTable(properties, "access_grant_projections");
    }

    public boolean hasActiveGrant(String tenant, String targetUserId, String granteeUserId, String requiredScope) {
        Integer count = jdbc.queryForObject("""
                SELECT count(*)
                  FROM %s
                 WHERE tenant = ?
                   AND target_user_id = ?
                   AND grantee_user_id = ?
                   AND status IN ('APPROVED','ACTIVE')
                   AND (expires_at IS NULL OR expires_at > now())
                   AND (
                        scope = ?
                        OR scope = 'todo:*'
                        OR scope = 'todo:*:*'
                        OR scope = 'todo:read'
                        OR scope = '*'
                   )
                """.formatted(tableName), Integer.class, tenant, targetUserId, granteeUserId, requiredScope);
        return count != null && count > 0;
    }

    public void upsertGrant(String grantId, String tenant, String targetUserId, String granteeUserId, String scope, String status, Instant expiresAt, String sourceEventId) {
        jdbc.update("""
                INSERT INTO %s (grant_id, tenant, target_user_id, grantee_user_id, scope, status, expires_at, source_event_id, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, now())
                ON CONFLICT (grant_id) DO UPDATE SET
                  tenant = EXCLUDED.tenant,
                  target_user_id = EXCLUDED.target_user_id,
                  grantee_user_id = EXCLUDED.grantee_user_id,
                  scope = EXCLUDED.scope,
                  status = EXCLUDED.status,
                  expires_at = EXCLUDED.expires_at,
                  source_event_id = EXCLUDED.source_event_id,
                  updated_at = now()
                """.formatted(tableName), grantId, tenant, targetUserId, granteeUserId, scope, normalizeStatus(status), expiresAt, sourceEventId);
    }

    public void revokeGrant(String grantId, String sourceEventId) {
        jdbc.update("""
                UPDATE %s
                   SET status = 'REVOKED', revoked_at = now(), source_event_id = ?, updated_at = now()
                 WHERE grant_id = ?
                """.formatted(tableName), sourceEventId, grantId);
    }

    private static String qualifiedTable(TodoProperties properties, String table) {
        String schema = properties.getPostgres().getSchema();
        if (schema == null || !schema.matches("[A-Za-z_][A-Za-z0-9_]*")) {
            throw new IllegalStateException("Invalid PostgreSQL schema name for todo_list_service");
        }
        return schema + "." + table;
    }

    private static String normalizeStatus(String status) {
        if (status == null || status.isBlank()) return "ACTIVE";
        String upper = status.trim().toUpperCase();
        if ("APPROVED".equals(upper)) return "ACTIVE";
        return upper;
    }
}
