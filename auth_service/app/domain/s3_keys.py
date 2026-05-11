from __future__ import annotations

from datetime import UTC, datetime

from app.config import Settings


def event_type_slug(event_type: str) -> str:
    return event_type.replace(".", "_").replace("-", "_")


def audit_snapshot_key(settings: Settings, *, actor_user_id: str, event_type: str, event_id: str, timestamp: datetime | None = None) -> str:
    timestamp = timestamp or datetime.now(UTC)
    return (
        f"{settings.service_name}/{settings.environment}/tenant/{settings.tenant}/users/{actor_user_id}/events/"
        f"{timestamp:%Y/%m/%d}/{timestamp:%H%M%S}_{event_type_slug(event_type)}_{event_id}.json"
    )
