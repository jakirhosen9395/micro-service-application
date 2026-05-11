from __future__ import annotations

import time
from collections.abc import Awaitable, Callable
from typing import Any

from app.config import Settings
from app.security.tokens import decode_access_token, encode_access_token
from app.utils.time import epoch_seconds, iso_now, utc_now

DependencyCheck = Callable[[], Awaitable[None]]


class HealthService:
    def __init__(self, settings: Settings, checks: dict[str, DependencyCheck]):
        self.settings = settings
        self.checks = checks

    async def check_jwt(self) -> None:
        now = utc_now()
        claims = {
            "iss": self.settings.jwt_issuer,
            "aud": self.settings.jwt_audience,
            "sub": "health-check",
            "jti": "health-check",
            "username": "health",
            "email": "health@auth_service.local",
            "role": "service",
            "admin_status": "not_requested",
            "tenant": self.settings.tenant,
            "status": "active",
            "iat": epoch_seconds(now),
            "nbf": epoch_seconds(now),
            "exp": epoch_seconds(now) + 60,
        }
        token = encode_access_token(self.settings, claims)
        decode_access_token(self.settings, token)

    async def health(self) -> tuple[int, dict[str, Any]]:
        dependencies: dict[str, dict[str, Any]] = {}
        all_checks: dict[str, DependencyCheck] = {"jwt": self.check_jwt, **self.checks}
        for name in ["jwt", "postgres", "redis", "kafka", "s3", "mongodb", "apm", "elasticsearch"]:
            check = all_checks[name]
            started = time.perf_counter()
            try:
                await check()
                dependencies[name] = {"status": "ok", "latency_ms": round((time.perf_counter() - started) * 1000, 3)}
            except Exception:
                dependencies[name] = {
                    "status": "down",
                    "latency_ms": round((time.perf_counter() - started) * 1000, 3),
                    "error_code": f"{name.upper()}_UNAVAILABLE",
                }
        status = "ok" if all(item["status"] == "ok" for item in dependencies.values()) else "down"
        return (200 if status == "ok" else 503), {
            "status": status,
            "service": {
                "name": self.settings.service_name,
                "environment": self.settings.environment,
                "version": self.settings.version,
            },
            "version": self.settings.version,
            "environment": self.settings.environment,
            "timestamp": iso_now(),
            "checks": {name: value["status"] for name, value in dependencies.items()},
            "dependencies": dependencies,
        }
