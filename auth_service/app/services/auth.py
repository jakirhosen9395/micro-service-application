from __future__ import annotations

import logging
from datetime import timedelta
from typing import Any

from fastapi import Request

from app.config import Settings
from app.domain.events import build_event_envelope
from app.domain.s3_keys import audit_snapshot_key
from app.domain.schemas import (
    AdminDecisionRequest,
    AdminRegisterRequest,
    ChangePasswordRequest,
    ForgotPasswordRequest,
    RefreshTokenRequest,
    ResetPasswordRequest,
    SigninRequest,
    SignupRequest,
)
from app.http.errors import bad_request, conflict, forbidden, not_found, unauthorized
from app.security.passwords import hash_password, validate_password_policy, verify_password
from app.security.tokens import (
    build_access_claims,
    encode_access_token,
    hash_opaque_token,
    new_password_reset_token,
    new_refresh_token,
    split_password_reset_token,
)
from app.utils.ids import new_event_id, new_id
from app.utils.redaction import redact
from app.utils.time import iso_now, isoformat, utc_now

logger = logging.getLogger("app.auth_service")


class AuthService:
    def __init__(self, settings: Settings, repository, redis_client, kafka_client, s3_client):
        self.settings = settings
        self.repository = repository
        self.redis = redis_client
        self.kafka = kafka_client
        self.s3 = s3_client

    def _safe_user(self, user: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": str(user["id"]),
            "username": user["username"],
            "email": user["email"],
            "full_name": user.get("full_name"),
            "birthdate": user.get("birthdate"),
            "gender": user.get("gender"),
            "role": user["role"],
            "admin_status": user["admin_status"],
            "tenant": user["tenant"],
            "status": user["status"],
            "email_verified": user.get("email_verified", False),
            "created_at": user.get("created_at"),
            "updated_at": user.get("updated_at"),
            "last_login_at": user.get("last_login_at"),
            "admin_requested_at": user.get("admin_requested_at"),
            "admin_reviewed_at": user.get("admin_reviewed_at"),
            "admin_reviewed_by": user.get("admin_reviewed_by"),
            "admin_request_reason": user.get("admin_request_reason"),
            "admin_decision_reason": user.get("admin_decision_reason"),
        }

    def _request_ids(self, request: Request) -> tuple[str | None, str | None, str | None]:
        return (
            getattr(request.state, "request_id", None),
            getattr(request.state, "trace_id", None),
            getattr(request.state, "correlation_id", None),
        )

    def _client_ip(self, request: Request) -> str | None:
        return request.client.host if request.client else None

    def _user_agent(self, request: Request) -> str | None:
        return request.headers.get("user-agent")

    def _event(self, request: Request, *, event_type: str, user_id: str | None, actor_id: str | None, aggregate_type: str, aggregate_id: str, payload: dict[str, Any] | None) -> dict[str, Any]:
        request_id, trace_id, correlation_id = self._request_ids(request)
        return build_event_envelope(
            self.settings,
            event_type=event_type,
            user_id=user_id,
            actor_id=actor_id,
            aggregate_type=aggregate_type,
            aggregate_id=aggregate_id,
            payload=payload,
            request_id=request_id,
            trace_id=trace_id,
            correlation_id=correlation_id,
        )

    def _audit_from_event(self, request: Request, event: dict[str, Any], *, target_user_id: str | None = None) -> tuple[dict[str, Any], dict[str, Any]]:
        now = utc_now()
        actor = event.get("actor_id") or event.get("user_id") or "system"
        s3_key = audit_snapshot_key(self.settings, actor_user_id=str(actor), event_type=event["event_type"], event_id=event["event_id"], timestamp=now)
        audit_body = {
            "event_id": event["event_id"],
            "event_type": event["event_type"],
            "service": self.settings.service_name,
            "environment": self.settings.environment,
            "tenant": self.settings.tenant,
            "user_id": event.get("user_id"),
            "actor_id": event.get("actor_id"),
            "target_user_id": target_user_id,
            "aggregate_type": event["aggregate_type"],
            "aggregate_id": event["aggregate_id"],
            "request_id": event.get("request_id"),
            "trace_id": event.get("trace_id"),
            "correlation_id": event.get("correlation_id"),
            "client_ip": self._client_ip(request),
            "user_agent": self._user_agent(request),
            "timestamp": now.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "payload": redact(event.get("payload", {})),
        }
        audit_row = {
            "id": new_id(),
            "event_id": event["event_id"],
            "event_type": event["event_type"],
            "service": self.settings.service_name,
            "environment": self.settings.environment,
            "tenant": self.settings.tenant,
            "user_id": event.get("user_id"),
            "actor_id": event.get("actor_id"),
            "target_user_id": target_user_id,
            "aggregate_type": event["aggregate_type"],
            "aggregate_id": event["aggregate_id"],
            "request_id": event.get("request_id"),
            "trace_id": event.get("trace_id"),
            "correlation_id": event.get("correlation_id"),
            "client_ip": self._client_ip(request),
            "user_agent": self._user_agent(request),
            "s3_bucket": self.settings.s3_bucket,
            "s3_object_key": s3_key,
            "payload": redact(event.get("payload", {})),
        }
        return audit_row, audit_body

    def _outbox(self, event: dict[str, Any], topic: str | None = None) -> dict[str, Any]:
        return {
            "event_id": event["event_id"],
            "tenant": event["tenant"],
            "aggregate_type": event["aggregate_type"],
            "aggregate_id": event["aggregate_id"],
            "event_type": event["event_type"],
            "event_version": event.get("event_version", "1.0"),
            "topic": topic or self.settings.kafka_events_topic,
            "payload": event,
            "request_id": event.get("request_id"),
            "trace_id": event.get("trace_id"),
            "correlation_id": event.get("correlation_id"),
        }

    async def _write_s3_audit(self, key: str, body: dict[str, Any]) -> None:
        try:
            await self.s3.put_json(key, body)
        except Exception as exc:
            logger.warning("S3 audit write failed", extra={"event": "s3.audit.write_failed", "error_code": "S3_AUDIT_WRITE_FAILED", "extra": {"error": str(exc), "s3_object_key": key}})
            failure = build_event_envelope(
                self.settings,
                event_type="auth.audit.s3_failed",
                user_id=body.get("user_id"),
                actor_id=body.get("actor_id"),
                aggregate_type=body.get("aggregate_type") or "audit",
                aggregate_id=body.get("aggregate_id") or body.get("event_id"),
                payload={"event_id": body.get("event_id"), "s3_object_key": key, "error_code": "S3_AUDIT_WRITE_FAILED"},
                request_id=body.get("request_id"),
                trace_id=body.get("trace_id"),
                correlation_id=body.get("correlation_id"),
            )
            await self.repository.insert_outbox_event(failure, self.settings.kafka_events_topic)

    async def _create_session_and_tokens(self, user: dict[str, Any], request: Request, device_id: str | None = None) -> tuple[dict[str, Any], dict[str, Any]]:
        now = utc_now()
        jti = new_id()
        refresh_token = new_refresh_token()
        claims = build_access_claims(self.settings, user, jti)
        access_token = encode_access_token(self.settings, claims)
        session = {
            "id": new_id(),
            "tenant": self.settings.tenant,
            "user_id": user["id"],
            "jti": jti,
            "refresh_token_hash": hash_opaque_token(refresh_token),
            "access_token_expires_at": now + timedelta(minutes=self.settings.access_token_expire_minutes),
            "refresh_token_expires_at": now + timedelta(days=self.settings.refresh_token_expire_days),
            "ip_address": self._client_ip(request),
            "user_agent": self._user_agent(request),
            "device_id": device_id,
        }
        tokens = {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "Bearer",
            "expires_in": self.settings.access_token_expire_minutes * 60,
        }
        return session, tokens

    async def signup(self, payload: SignupRequest, request: Request) -> dict[str, Any]:
        validate_password_policy(payload.password, self.settings)
        if payload.account_type == "admin":
            if not payload.reason:
                raise bad_request("Admin signup requires reason", "ADMIN_REASON_REQUIRED")
            admin_payload = AdminRegisterRequest(**payload.model_dump())
            return await self.admin_register(admin_payload, request)
        if await self.repository.username_or_email_exists(payload.username, str(payload.email)):
            raise conflict("Username or email already exists", "USER_ALREADY_EXISTS")
        user = {
            "id": new_id(),
            "tenant": self.settings.tenant,
            "username": payload.username,
            "email": str(payload.email).lower(),
            "password_hash": hash_password(payload.password),
            "full_name": payload.full_name,
            "birthdate": payload.birthdate,
            "gender": payload.gender,
            "role": "user",
            "admin_status": "not_requested",
            "status": "active",
            "email_verified": False,
            "admin_requested_at": None,
            "admin_request_reason": None,
        }
        session, tokens = await self._create_session_and_tokens(user, request)
        event = self._event(request, event_type="auth.user.signed_up", user_id=user["id"], actor_id=user["id"], aggregate_type="user", aggregate_id=user["id"], payload={"user": self._safe_user(user)})
        audit, audit_body = self._audit_from_event(request, event, target_user_id=user["id"])
        await self.repository.create_user_with_optional_session(user=user, session=session, audit=audit, outbox=[self._outbox(event)])
        await self.redis.set_json(self.redis.key("session", session["jti"]), {"user_id": user["id"], "status": "active"}, self.settings.access_token_expire_minutes * 60)
        await self._write_s3_audit(audit["s3_object_key"], audit_body)
        return {"user": self._safe_user(user), "tokens": tokens}

    async def admin_register(self, payload: AdminRegisterRequest, request: Request) -> dict[str, Any]:
        validate_password_policy(payload.password, self.settings)
        if await self.repository.username_or_email_exists(payload.username, str(payload.email)):
            raise conflict("Username or email already exists", "USER_ALREADY_EXISTS")
        user = {
            "id": new_id(),
            "tenant": self.settings.tenant,
            "username": payload.username,
            "email": str(payload.email).lower(),
            "password_hash": hash_password(payload.password),
            "full_name": payload.full_name,
            "birthdate": payload.birthdate,
            "gender": payload.gender,
            "role": "admin",
            "admin_status": "pending",
            "status": "active",
            "email_verified": False,
            "admin_requested_at": utc_now(),
            "admin_request_reason": payload.reason,
        }
        event = self._event(request, event_type="auth.admin.registration_requested", user_id=user["id"], actor_id=user["id"], aggregate_type="admin_registration_request", aggregate_id=user["id"], payload={"user": self._safe_user(user), "reason": payload.reason})
        audit, audit_body = self._audit_from_event(request, event, target_user_id=user["id"])
        await self.repository.create_user_with_optional_session(user=user, session=None, audit=audit, outbox=[self._outbox(event, "auth.admin.requests")])
        await self._write_s3_audit(audit["s3_object_key"], audit_body)
        return {"user": self._safe_user(user), "request_status": "pending"}

    async def signin(self, payload: SigninRequest, request: Request) -> dict[str, Any]:
        user = await self.repository.fetch_user_by_username_or_email(payload.username_or_email)
        if not user or not verify_password(payload.password, user["password_hash"]):
            if user:
                await self.repository.record_failed_login(user["id"])
            raise unauthorized("Invalid username/email or password", "INVALID_CREDENTIALS")
        if user["status"] != "active":
            raise forbidden("User account is not active", "USER_NOT_ACTIVE")
        session, tokens = await self._create_session_and_tokens(user, request, payload.device_id)
        event = self._event(request, event_type="auth.user.signed_in", user_id=user["id"], actor_id=user["id"], aggregate_type="session", aggregate_id=session["id"], payload={"user_id": user["id"], "username": user["username"], "role": user["role"], "admin_status": user["admin_status"]})
        audit, audit_body = self._audit_from_event(request, event, target_user_id=user["id"])
        await self.repository.signin_with_session(user_id=user["id"], session=session, audit=audit, outbox=[self._outbox(event)])
        await self.redis.set_json(self.redis.key("session", session["jti"]), {"user_id": user["id"], "status": "active"}, self.settings.access_token_expire_minutes * 60)
        await self._write_s3_audit(audit["s3_object_key"], audit_body)
        fresh = await self.repository.fetch_user_by_id(user["id"])
        return {"user": self._safe_user(fresh or user), "tokens": tokens}

    async def logout(self, claims: dict[str, Any], request: Request) -> dict[str, Any]:
        jti = claims["jti"]
        event = self._event(request, event_type="auth.user.logged_out", user_id=claims["sub"], actor_id=claims["sub"], aggregate_type="session", aggregate_id=jti, payload={"user_id": claims["sub"]})
        audit, audit_body = self._audit_from_event(request, event, target_user_id=claims["sub"])
        await self.repository.revoke_session_with_event(jti=jti, reason="logout", audit=audit, outbox=[self._outbox(event)])
        await self.redis.set_value(self.redis.key("token", "blacklist", jti), "revoked", self.settings.access_token_expire_minutes * 60)
        await self.redis.delete(self.redis.key("session", jti))
        await self._write_s3_audit(audit["s3_object_key"], audit_body)
        return {"revoked": True}

    async def refresh(self, payload: RefreshTokenRequest, request: Request) -> dict[str, Any]:
        token_hash = hash_opaque_token(payload.refresh_token)
        session = await self.repository.fetch_session_by_refresh_hash(token_hash)
        if not session or session.get("revoked_at") is not None or session["refresh_token_expires_at"] <= utc_now():
            raise unauthorized("Invalid refresh token", "INVALID_REFRESH_TOKEN")
        user = await self.repository.fetch_user_by_id(session["user_id"])
        if not user or user["status"] != "active":
            raise unauthorized("Invalid refresh token", "INVALID_REFRESH_TOKEN")
        old_jti = session["jti"]
        new_jti = new_id()
        refresh_token = new_refresh_token()
        now = utc_now()
        claims = build_access_claims(self.settings, user, new_jti)
        tokens = {
            "access_token": encode_access_token(self.settings, claims),
            "refresh_token": refresh_token,
            "token_type": "Bearer",
            "expires_in": self.settings.access_token_expire_minutes * 60,
        }
        event = self._event(request, event_type="auth.token.refreshed", user_id=user["id"], actor_id=user["id"], aggregate_type="session", aggregate_id=session["id"], payload={"user_id": user["id"]})
        audit, audit_body = self._audit_from_event(request, event, target_user_id=user["id"])
        await self.repository.rotate_session_with_event(
            session_id=session["id"],
            new_jti=new_jti,
            refresh_token_hash=hash_opaque_token(refresh_token),
            access_expires_at=now + timedelta(minutes=self.settings.access_token_expire_minutes),
            refresh_expires_at=now + timedelta(days=self.settings.refresh_token_expire_days),
            audit=audit,
            outbox=[self._outbox(event)],
        )
        await self.redis.set_value(self.redis.key("token", "blacklist", old_jti), "rotated", self.settings.access_token_expire_minutes * 60)
        await self.redis.delete(self.redis.key("session", old_jti))
        await self.redis.set_json(self.redis.key("session", new_jti), {"user_id": user["id"], "status": "active"}, self.settings.access_token_expire_minutes * 60)
        await self._write_s3_audit(audit["s3_object_key"], audit_body)
        return {"user": self._safe_user(user), "tokens": tokens}

    async def me(self, claims: dict[str, Any]) -> dict[str, Any]:
        user = await self.repository.fetch_user_by_id(claims["sub"])
        if not user:
            raise not_found("User not found", "USER_NOT_FOUND")
        return self._safe_user(user)

    async def verify(self, claims: dict[str, Any]) -> dict[str, Any]:
        user = await self.repository.fetch_user_by_id(claims["sub"])
        return {"active": bool(user and user["status"] == "active"), "claims": claims, "user": self._safe_user(user) if user else None}

    async def forgot_password(self, payload: ForgotPasswordRequest, request: Request) -> dict[str, Any]:
        user = await self.repository.fetch_user_by_username_or_email(payload.lookup_value)
        if user:
            token_id, reset_token = new_password_reset_token()
            _, secret = split_password_reset_token(reset_token)
            await self.redis.set_json(
                self.redis.key("password-reset", token_id),
                {"user_id": user["id"], "secret_hash": hash_opaque_token(secret), "created_at": iso_now()},
                900,
            )
            event = self._event(request, event_type="auth.password.reset_requested", user_id=user["id"], actor_id=user["id"], aggregate_type="user", aggregate_id=user["id"], payload={"user_id": user["id"]})
            audit, audit_body = self._audit_from_event(request, event, target_user_id=user["id"])
            await self.repository.record_audit_and_outbox(audit=audit, outbox=[self._outbox(event)])
            await self._write_s3_audit(audit["s3_object_key"], audit_body)
            # No email service exists in this auth boundary; non-production receives the token for local testing.
            if self.settings.environment != "production":
                return {"accepted": True, "reset_token": reset_token}
        return {"accepted": True}

    async def reset_password(self, payload: ResetPasswordRequest, request: Request) -> dict[str, Any]:
        validate_password_policy(payload.new_password, self.settings)
        try:
            token_id, secret = split_password_reset_token(payload.effective_token)
        except ValueError as exc:
            raise bad_request("Invalid reset token", "INVALID_RESET_TOKEN") from exc
        key = self.redis.key("password-reset", token_id)
        stored = await self.redis.get_json(key)
        if not stored or stored.get("secret_hash") != hash_opaque_token(secret):
            raise bad_request("Invalid reset token", "INVALID_RESET_TOKEN")
        user = await self.repository.fetch_user_by_id(stored["user_id"])
        if not user:
            raise not_found("User not found", "USER_NOT_FOUND")
        event = self._event(request, event_type="auth.password.reset_completed", user_id=user["id"], actor_id=user["id"], aggregate_type="user", aggregate_id=user["id"], payload={"user_id": user["id"]})
        audit, audit_body = self._audit_from_event(request, event, target_user_id=user["id"])
        await self.repository.update_password_with_event(user_id=user["id"], password_hash=hash_password(payload.new_password), audit=audit, outbox=[self._outbox(event)])
        await self.redis.delete(key)
        await self._write_s3_audit(audit["s3_object_key"], audit_body)
        return {"password_reset": True}

    async def change_password(self, payload: ChangePasswordRequest, claims: dict[str, Any], request: Request) -> dict[str, Any]:
        validate_password_policy(payload.new_password, self.settings)
        user = await self.repository.fetch_user_by_id(claims["sub"])
        if not user:
            raise not_found("User not found", "USER_NOT_FOUND")
        if not verify_password(payload.current_password, user["password_hash"]):
            raise unauthorized("Current password is invalid", "INVALID_CURRENT_PASSWORD")
        event = self._event(request, event_type="auth.password.changed", user_id=user["id"], actor_id=user["id"], aggregate_type="user", aggregate_id=user["id"], payload={"user_id": user["id"]})
        audit, audit_body = self._audit_from_event(request, event, target_user_id=user["id"])
        await self.repository.update_password_with_event(user_id=user["id"], password_hash=hash_password(payload.new_password), audit=audit, outbox=[self._outbox(event)])
        await self.redis.set_value(self.redis.key("token", "blacklist", claims["jti"]), "password_changed", self.settings.access_token_expire_minutes * 60)
        await self._write_s3_audit(audit["s3_object_key"], audit_body)
        return {"password_changed": True}

    async def list_admin_requests(self) -> list[dict[str, Any]]:
        users = await self.repository.list_admin_requests()
        return [self._safe_user(user) for user in users]

    async def decide_admin_request(self, user_id: str, payload: AdminDecisionRequest, claims: dict[str, Any], request: Request) -> dict[str, Any]:
        event_type = "auth.admin.registration_approved" if payload.decision == "approve" else "auth.admin.registration_rejected"
        event = self._event(
            request,
            event_type=event_type,
            user_id=user_id,
            actor_id=claims["sub"],
            aggregate_type="admin_registration_request",
            aggregate_id=user_id,
            payload={"target_user_id": user_id, "decision": payload.decision, "reason": payload.reason, "reviewer_id": claims["sub"]},
        )
        audit, audit_body = self._audit_from_event(request, event, target_user_id=user_id)
        user = await self.repository.decide_admin_request_with_event(
            user_id=user_id,
            reviewer_id=claims["sub"],
            decision=payload.decision,
            reason=payload.reason,
            audit=audit,
            outbox=[self._outbox(event, "auth.admin.decisions")],
        )
        if not user:
            raise not_found("Pending admin request not found", "ADMIN_REQUEST_NOT_FOUND")
        await self._write_s3_audit(audit["s3_object_key"], audit_body)
        return {"user": self._safe_user(user), "decision": payload.decision}

    async def ensure_token_session_active(self, claims: dict[str, Any]) -> None:
        jti = claims.get("jti")
        if not jti:
            raise unauthorized("Invalid token", "INVALID_TOKEN")
        if await self.redis.exists(self.redis.key("token", "blacklist", jti)):
            raise unauthorized("Token has been revoked", "TOKEN_REVOKED")
        cached = await self.redis.get_json(self.redis.key("session", jti))
        if cached and cached.get("status") == "active":
            return
        session = await self.repository.fetch_session_by_jti(jti)
        if not session or session.get("revoked_at") is not None:
            raise unauthorized("Session is not active", "SESSION_INACTIVE")
        if session["access_token_expires_at"] <= utc_now():
            raise unauthorized("Token expired", "TOKEN_EXPIRED")
        await self.redis.set_json(self.redis.key("session", jti), {"user_id": session["user_id"], "status": "active"}, self.settings.access_token_expire_minutes * 60)
