from __future__ import annotations

from typing import Any

from app.config import Settings
from app.utils.ids import new_event_id
from app.utils.redaction import redact
from app.utils.time import iso_now


def build_event_envelope(
    settings: Settings,
    *,
    event_type: str,
    user_id: str | None,
    actor_id: str | None,
    aggregate_type: str,
    aggregate_id: str,
    payload: dict[str, Any] | None,
    request_id: str | None,
    trace_id: str | None,
    correlation_id: str | None,
    event_id: str | None = None,
) -> dict[str, Any]:
    return {
        "event_id": event_id or new_event_id(),
        "event_type": event_type,
        "event_version": "1.0",
        "service": settings.service_name,
        "environment": settings.environment,
        "tenant": settings.tenant,
        "timestamp": iso_now(),
        "request_id": request_id,
        "trace_id": trace_id,
        "correlation_id": correlation_id,
        "user_id": user_id,
        "actor_id": actor_id,
        "aggregate_type": aggregate_type,
        "aggregate_id": aggregate_id,
        "payload": redact(payload or {}),
    }


def kafka_key(envelope: dict[str, Any]) -> str:
    tenant = envelope.get("tenant") or "unknown"
    user_id = envelope.get("user_id")
    aggregate_id = envelope.get("aggregate_id")
    return f"{tenant}:{user_id or aggregate_id}"


def kafka_headers(envelope: dict[str, Any]) -> list[tuple[str, bytes]]:
    names = ["event_id", "event_type", "service", "tenant", "trace_id", "correlation_id"]
    headers: list[tuple[str, bytes]] = []
    for name in names:
        value = envelope.get(name)
        if value is not None:
            headers.append((name, str(value).encode("utf-8")))
    return headers
