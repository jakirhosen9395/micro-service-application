from __future__ import annotations

from collections.abc import Mapping, Sequence

SECRET_MARKERS = (
    "password",
    "secret",
    "token",
    "authorization",
    "cookie",
    "jwt",
    "access_key",
    "secret_key",
    "refresh",
)


def is_secret_key(key: str) -> bool:
    lowered = key.lower()
    return any(marker in lowered for marker in SECRET_MARKERS)


def redact(value):
    if isinstance(value, Mapping):
        return {key: "***REDACTED***" if is_secret_key(str(key)) else redact(item) for key, item in value.items()}
    if isinstance(value, list | tuple):
        return [redact(item) for item in value]
    return value
