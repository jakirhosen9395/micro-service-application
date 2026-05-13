from __future__ import annotations

import logging
from datetime import UTC, datetime

from app.config import Settings
from app.security.passwords import hash_password
from app.utils.ids import new_id

logger = logging.getLogger("app.bootstrap")


async def bootstrap_default_admin(repository, settings: Settings) -> None:
    existing = await repository.fetch_user_by_username_or_email(settings.default_admin_username)
    if existing:
        return
    user = {
        "id": new_id(),
        "tenant": settings.tenant,
        "username": settings.default_admin_username,
        "email": settings.default_admin_email,
        "password_hash": hash_password(settings.default_admin_password),
        "full_name": settings.default_admin_full_name,
        "birthdate": None,
        "gender": "prefer_not_to_say",
        "role": "admin",
        "admin_status": "approved",
        "status": "active",
        "email_verified": True,
        "admin_requested_at": datetime.now(UTC),
        "admin_request_reason": "Default bootstrap administrator",
    }
    audit = {
        "id": new_id(),
        "event_id": new_id("evt"),
        "event_type": "auth.default_admin.bootstrapped",
        "service": settings.service_name,
        "environment": settings.environment,
        "tenant": settings.tenant,
        "user_id": user["id"],
        "actor_id": "system",
        "target_user_id": user["id"],
        "aggregate_type": "user",
        "aggregate_id": user["id"],
        "request_id": None,
        "trace_id": None,
        "correlation_id": None,
        "client_ip": None,
        "user_agent": None,
        "s3_bucket": None,
        "s3_object_key": None,
        "payload": {"username": user["username"], "email": user["email"], "role": "admin", "admin_status": "approved"},
    }
    await repository.create_user_with_optional_session(user=user, session=None, audit=audit, outbox=[])
    logger.info("default admin bootstrapped", extra={"event": "auth.default_admin.bootstrapped", "user_id": user["id"]})
