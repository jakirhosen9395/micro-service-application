from __future__ import annotations

from uuid import uuid4


def new_id(prefix: str | None = None) -> str:
    value = str(uuid4())
    return f"{prefix}-{value}" if prefix else value


def new_event_id() -> str:
    return new_id("evt")


def new_request_id() -> str:
    return new_id("req")


def new_trace_id() -> str:
    return uuid4().hex
