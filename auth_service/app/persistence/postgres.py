from __future__ import annotations

import json
import logging
from typing import Any

from app.config import Settings, project_root
from app.utils.redaction import redact

logger = logging.getLogger("app.postgres")


class PostgresRepository:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.pool = None

    async def connect(self) -> None:
        try:
            import asyncpg
        except ImportError as exc:
            raise RuntimeError("asyncpg is required for PostgreSQL integration") from exc
        self.pool = await asyncpg.create_pool(
            host=self.settings.postgres_host,
            port=self.settings.postgres_port,
            user=self.settings.postgres_user,
            password=self.settings.postgres_password,
            database=self.settings.postgres_db,
            min_size=1,
            max_size=self.settings.postgres_pool_size,
            server_settings={"search_path": self.settings.postgres_schema},
            command_timeout=30,
        )

    async def close(self) -> None:
        if self.pool is not None:
            await self.pool.close()

    async def migrate(self) -> None:
        if self.settings.postgres_migration_mode != "auto":
            return
        if self.pool is None:
            raise RuntimeError("PostgreSQL pool is not initialized")
        migration = project_root() / "migrations" / "001_auth_schema.sql"
        sql = migration.read_text(encoding="utf-8")
        async with self.pool.acquire() as conn:
            await conn.execute(sql)

    async def health(self) -> None:
        if self.pool is None:
            raise RuntimeError("PostgreSQL pool is not initialized")
        async with self.pool.acquire() as conn:
            await conn.execute("select 1")

    async def fetch_user_by_username_or_email(self, value: str) -> dict[str, Any] | None:
        sql = """
        select * from auth.auth_users
        where tenant=$1 and deleted_at is null and (lower(username)=lower($2) or lower(email)=lower($2))
        limit 1
        """
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(sql, self.settings.tenant, value)
        return dict(row) if row else None

    async def fetch_user_by_id(self, user_id: str) -> dict[str, Any] | None:
        sql = "select * from auth.auth_users where tenant=$1 and id=$2 and deleted_at is null"
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(sql, self.settings.tenant, user_id)
        return dict(row) if row else None

    async def fetch_user_by_email(self, email: str) -> dict[str, Any] | None:
        sql = "select * from auth.auth_users where tenant=$1 and lower(email)=lower($2) and deleted_at is null"
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(sql, self.settings.tenant, email)
        return dict(row) if row else None

    async def username_or_email_exists(self, username: str, email: str) -> bool:
        sql = """
        select 1 from auth.auth_users
        where tenant=$1 and deleted_at is null and (lower(username)=lower($2) or lower(email)=lower($3))
        limit 1
        """
        async with self.pool.acquire() as conn:
            return bool(await conn.fetchval(sql, self.settings.tenant, username, email))

    async def list_admin_requests(self, limit: int = 100, offset: int = 0) -> list[dict[str, Any]]:
        sql = """
        select * from auth.auth_users
        where tenant=$1 and role='admin' and admin_status in ('pending','approved','rejected','suspended') and deleted_at is null
        order by coalesce(admin_requested_at, created_at) desc
        limit $2 offset $3
        """
        async with self.pool.acquire() as conn:
            rows = await conn.fetch(sql, self.settings.tenant, limit, offset)
        return [dict(row) for row in rows]

    async def fetch_session_by_jti(self, jti: str) -> dict[str, Any] | None:
        sql = "select * from auth.auth_sessions where tenant=$1 and jti=$2 limit 1"
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(sql, self.settings.tenant, jti)
        return dict(row) if row else None

    async def fetch_session_by_refresh_hash(self, token_hash: str) -> dict[str, Any] | None:
        sql = "select * from auth.auth_sessions where tenant=$1 and refresh_token_hash=$2 limit 1"
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(sql, self.settings.tenant, token_hash)
        return dict(row) if row else None

    async def create_user_with_optional_session(
        self,
        *,
        user: dict[str, Any],
        session: dict[str, Any] | None,
        audit: dict[str, Any],
        outbox: list[dict[str, Any]],
    ) -> None:
        if self.pool is None:
            raise RuntimeError("PostgreSQL pool is not initialized")
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                await self._insert_user(conn, user)
                if session is not None:
                    await self._insert_session(conn, session)
                await self._insert_audit(conn, audit)
                for event in outbox:
                    await self._insert_outbox(conn, event)

    async def signin_with_session(self, *, user_id: str, session: dict[str, Any], audit: dict[str, Any], outbox: list[dict[str, Any]]) -> None:
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                await conn.execute(
                    "update auth.auth_users set last_login_at=now(), last_seen_at=now(), failed_login_count=0, updated_at=now() where tenant=$1 and id=$2",
                    self.settings.tenant,
                    user_id,
                )
                await self._insert_session(conn, session)
                await self._insert_audit(conn, audit)
                for event in outbox:
                    await self._insert_outbox(conn, event)

    async def record_failed_login(self, user_id: str) -> None:
        async with self.pool.acquire() as conn:
            await conn.execute(
                "update auth.auth_users set failed_login_count=failed_login_count+1, updated_at=now() where tenant=$1 and id=$2",
                self.settings.tenant,
                user_id,
            )

    async def revoke_session_with_event(self, *, jti: str, reason: str, audit: dict[str, Any], outbox: list[dict[str, Any]]) -> None:
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                await conn.execute(
                    "update auth.auth_sessions set revoked_at=now(), revoked_reason=$3 where tenant=$1 and jti=$2 and revoked_at is null",
                    self.settings.tenant,
                    jti,
                    reason,
                )
                await self._insert_audit(conn, audit)
                for event in outbox:
                    await self._insert_outbox(conn, event)

    async def rotate_session_with_event(
        self,
        *,
        session_id: str,
        new_jti: str,
        refresh_token_hash: str,
        access_expires_at,
        refresh_expires_at,
        audit: dict[str, Any],
        outbox: list[dict[str, Any]],
    ) -> None:
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                await conn.execute(
                    """
                    update auth.auth_sessions
                    set jti=$3, refresh_token_hash=$4, access_token_expires_at=$5, refresh_token_expires_at=$6, last_seen_at=now()
                    where tenant=$1 and id=$2 and revoked_at is null
                    """,
                    self.settings.tenant,
                    session_id,
                    new_jti,
                    refresh_token_hash,
                    access_expires_at,
                    refresh_expires_at,
                )
                await self._insert_audit(conn, audit)
                for event in outbox:
                    await self._insert_outbox(conn, event)

    async def update_password_with_event(self, *, user_id: str, password_hash: str, audit: dict[str, Any], outbox: list[dict[str, Any]]) -> None:
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                await conn.execute(
                    "update auth.auth_users set password_hash=$3, updated_at=now() where tenant=$1 and id=$2",
                    self.settings.tenant,
                    user_id,
                    password_hash,
                )
                await conn.execute(
                    "update auth.auth_sessions set revoked_at=now(), revoked_reason='password_changed' where tenant=$1 and user_id=$2 and revoked_at is null",
                    self.settings.tenant,
                    user_id,
                )
                await self._insert_audit(conn, audit)
                for event in outbox:
                    await self._insert_outbox(conn, event)

    async def decide_admin_request_with_event(
        self,
        *,
        user_id: str,
        reviewer_id: str,
        decision: str,
        reason: str,
        audit: dict[str, Any],
        outbox: list[dict[str, Any]],
    ) -> dict[str, Any] | None:
        status = "approved" if decision == "approve" else "rejected"
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                row = await conn.fetchrow(
                    """
                    update auth.auth_users
                    set admin_status=$4, admin_reviewed_at=now(), admin_reviewed_by=$3, admin_decision_reason=$5, updated_at=now()
                    where tenant=$1 and id=$2 and role='admin' and admin_status='pending' and deleted_at is null
                    returning *
                    """,
                    self.settings.tenant,
                    user_id,
                    reviewer_id,
                    status,
                    reason,
                )
                if not row:
                    return None
                await self._insert_audit(conn, audit)
                for event in outbox:
                    await self._insert_outbox(conn, event)
                return dict(row)

    async def record_audit_and_outbox(self, *, audit: dict[str, Any], outbox: list[dict[str, Any]]) -> None:
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                await self._insert_audit(conn, audit)
                for event in outbox:
                    await self._insert_outbox(conn, event)

    async def insert_outbox_event(self, event: dict[str, Any], topic: str) -> None:
        async with self.pool.acquire() as conn:
            await self._insert_outbox(conn, self._outbox_from_envelope(event, topic))

    async def fetch_pending_outbox(self, limit: int = 50) -> list[dict[str, Any]]:
        sql = """
        update auth.outbox_events
        set status='PROCESSING', updated_at=now()
        where id in (
          select id from auth.outbox_events
          where status in ('PENDING','FAILED') and (next_retry_at is null or next_retry_at <= now())
          order by created_at
          limit $1
          for update skip locked
        )
        returning *
        """
        async with self.pool.acquire() as conn:
            rows = await conn.fetch(sql, limit)
        return [dict(row) for row in rows]

    async def mark_outbox_sent(self, row_id: str) -> None:
        async with self.pool.acquire() as conn:
            await conn.execute("update auth.outbox_events set status='SENT', sent_at=now(), updated_at=now() where id=$1", row_id)

    async def mark_outbox_failed(self, row_id: str, error: str, max_attempts: int = 10) -> None:
        async with self.pool.acquire() as conn:
            await conn.execute(
                """
                update auth.outbox_events
                set status=case when attempt_count + 1 >= $3 then 'DEAD_LETTERED' else 'FAILED' end,
                    attempt_count=attempt_count+1,
                    last_error=$2,
                    next_retry_at=now() + interval '30 seconds',
                    updated_at=now()
                where id=$1
                """,
                row_id,
                error[:2000],
                max_attempts,
            )

    async def insert_inbox_event(
        self,
        *,
        event_id: str,
        tenant: str | None,
        topic: str,
        partition: int,
        offset: int,
        event_type: str,
        source_service: str | None,
        payload: dict[str, Any],
    ) -> bool:
        sql = """
        insert into auth.kafka_inbox_events(event_id, tenant, topic, partition, offset_value, event_type, source_service, payload, status)
        values ($1,$2,$3,$4,$5,$6,$7,$8::jsonb,'RECEIVED')
        on conflict do nothing
        """
        async with self.pool.acquire() as conn:
            result = await conn.execute(
                sql,
                event_id,
                tenant,
                topic,
                partition,
                offset,
                event_type,
                source_service,
                json.dumps(redact(payload), default=str),
            )
        return result.endswith("1")

    async def mark_inbox_processed(self, event_id: str, status: str = "PROCESSED", error: str | None = None) -> None:
        async with self.pool.acquire() as conn:
            await conn.execute(
                "update auth.kafka_inbox_events set status=$2, processed_at=now(), error_message=$3 where event_id=$1",
                event_id,
                status,
                error,
            )

    async def apply_admin_decision_event(self, envelope: dict[str, Any]) -> bool:
        """Apply admin registration decisions emitted by admin_service.

        admin_service owns the approval UI/workflow, but auth_service owns the
        login user row and the JWT claims. Without this projection, a newly
        approved admin remains admin_status='pending' in auth.auth_users and
        continues to receive 403 from admin_service after signin.
        """
        event_type = str(envelope.get("event_type") or "").lower()
        if not event_type.startswith("admin.registration.") and not event_type.startswith("auth.admin.registration_"):
            return False

        payload = envelope.get("payload") or {}
        if not isinstance(payload, dict):
            return False

        decision = str(payload.get("decision") or payload.get("status") or "").lower()
        if not decision:
            if event_type.endswith("approved") or event_type.endswith(".approved"):
                decision = "approved"
            elif event_type.endswith("rejected") or event_type.endswith(".rejected"):
                decision = "rejected"

        if decision in {"approve", "approved"}:
            admin_status = "approved"
        elif decision in {"reject", "rejected"}:
            admin_status = "rejected"
        else:
            return False

        tenant = envelope.get("tenant") or self.settings.tenant
        if tenant != self.settings.tenant:
            return False

        user_id = (
            payload.get("user_id")
            or payload.get("target_user_id")
            or envelope.get("user_id")
            or envelope.get("aggregate_id")
        )
        if not user_id:
            return False

        reviewer_id = payload.get("reviewed_by") or payload.get("actor_id") or envelope.get("actor_id")
        reason = payload.get("reason") or payload.get("decision_reason") or ""

        async with self.pool.acquire() as conn:
            result = await conn.execute(
                """
                update auth.auth_users
                set admin_status=$3,
                    admin_reviewed_at=now(),
                    admin_reviewed_by=$4,
                    admin_decision_reason=$5,
                    status='active',
                    updated_at=now()
                where tenant=$1
                  and id=$2
                  and role='admin'
                  and deleted_at is null
                """,
                tenant,
                str(user_id),
                admin_status,
                str(reviewer_id) if reviewer_id else None,
                str(reason),
            )
        return result.endswith("1")

    async def _insert_user(self, conn, user: dict[str, Any]) -> None:
        await conn.execute(
            """
            insert into auth.auth_users(
              id, tenant, username, email, password_hash, full_name, birthdate, gender, role, admin_status, status,
              email_verified, admin_requested_at, admin_request_reason, created_at, updated_at
            ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,now(),now())
            """,
            user["id"],
            user["tenant"],
            user["username"],
            user["email"],
            user["password_hash"],
            user.get("full_name"),
            user.get("birthdate"),
            user.get("gender"),
            user["role"],
            user["admin_status"],
            user.get("status", "active"),
            user.get("email_verified", False),
            user.get("admin_requested_at"),
            user.get("admin_request_reason"),
        )

    async def _insert_session(self, conn, session: dict[str, Any]) -> None:
        await conn.execute(
            """
            insert into auth.auth_sessions(
              id, tenant, user_id, jti, refresh_token_hash, access_token_expires_at, refresh_token_expires_at,
              ip_address, user_agent, device_id, created_at, last_seen_at
            ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,now(),now())
            """,
            session["id"],
            session["tenant"],
            session["user_id"],
            session["jti"],
            session["refresh_token_hash"],
            session["access_token_expires_at"],
            session["refresh_token_expires_at"],
            session.get("ip_address"),
            session.get("user_agent"),
            session.get("device_id"),
        )

    async def _insert_audit(self, conn, audit: dict[str, Any]) -> None:
        await conn.execute(
            """
            insert into auth.auth_audit_events(
              id, event_id, event_type, service, environment, tenant, user_id, actor_id, target_user_id,
              aggregate_type, aggregate_id, request_id, trace_id, correlation_id, client_ip, user_agent,
              s3_bucket, s3_object_key, payload, created_at
            ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19::jsonb,now())
            """,
            audit["id"],
            audit["event_id"],
            audit["event_type"],
            audit["service"],
            audit["environment"],
            audit["tenant"],
            audit.get("user_id"),
            audit.get("actor_id"),
            audit.get("target_user_id"),
            audit["aggregate_type"],
            audit["aggregate_id"],
            audit.get("request_id"),
            audit.get("trace_id"),
            audit.get("correlation_id"),
            audit.get("client_ip"),
            audit.get("user_agent"),
            audit.get("s3_bucket"),
            audit.get("s3_object_key"),
            json.dumps(redact(audit.get("payload", {})), default=str),
        )

    def _outbox_from_envelope(self, envelope: dict[str, Any], topic: str) -> dict[str, Any]:
        return {
            "event_id": envelope["event_id"],
            "tenant": envelope["tenant"],
            "aggregate_type": envelope["aggregate_type"],
            "aggregate_id": envelope["aggregate_id"],
            "event_type": envelope["event_type"],
            "event_version": envelope.get("event_version", "1.0"),
            "topic": topic,
            "payload": envelope,
            "request_id": envelope.get("request_id"),
            "trace_id": envelope.get("trace_id"),
            "correlation_id": envelope.get("correlation_id"),
        }

    async def _insert_outbox(self, conn, event: dict[str, Any]) -> None:
        await conn.execute(
            """
            insert into auth.outbox_events(
              event_id, tenant, aggregate_type, aggregate_id, event_type, event_version, topic, payload,
              request_id, trace_id, correlation_id, status, created_at, updated_at
            ) values ($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9,$10,$11,'PENDING',now(),now())
            on conflict (event_id) do nothing
            """,
            event["event_id"],
            event["tenant"],
            event["aggregate_type"],
            event["aggregate_id"],
            event["event_type"],
            event.get("event_version", "1.0"),
            event["topic"],
            json.dumps(redact(event["payload"]), default=str),
            event.get("request_id"),
            event.get("trace_id"),
            event.get("correlation_id"),
        )


# Elastic APM dependency spans are attached dynamically so every repository
# operation appears under APM Dependencies without rewriting each SQL method.
def _instrument_postgres_methods() -> None:
    from app.observability.apm import apm_span

    method_names = [
        "connect",
        "migrate",
        "health",
        "fetch_user_by_username_or_email",
        "fetch_user_by_id",
        "fetch_user_by_email",
        "username_or_email_exists",
        "list_admin_requests",
        "fetch_session_by_jti",
        "fetch_session_by_refresh_hash",
        "create_user_with_optional_session",
        "signin_with_session",
        "record_failed_login",
        "revoke_session_with_event",
        "rotate_session_with_event",
        "update_password_with_event",
        "decide_admin_request_with_event",
        "record_audit_and_outbox",
        "insert_outbox_event",
        "fetch_pending_outbox",
        "mark_outbox_sent",
        "mark_outbox_failed",
        "insert_inbox_event",
        "mark_inbox_processed",
        "apply_admin_decision_event",
    ]

    for method_name in method_names:
        original = getattr(PostgresRepository, method_name)
        if getattr(original, "_apm_instrumented", False):
            continue

        async def wrapped(self, *args, __original=original, __name=method_name, **kwargs):
            async with apm_span(f"PostgreSQL {__name}", "db.postgresql", labels={"db_system": "postgresql"}):
                return await __original(self, *args, **kwargs)

        wrapped.__name__ = original.__name__
        wrapped.__doc__ = original.__doc__
        wrapped._apm_instrumented = True
        setattr(PostgresRepository, method_name, wrapped)


_instrument_postgres_methods()

