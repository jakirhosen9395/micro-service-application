from __future__ import annotations

import json
from typing import Any

from app.config import Settings


class RedisClient:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.client = None

    async def connect(self) -> None:
        try:
            import redis.asyncio as redis
        except ImportError as exc:
            raise RuntimeError("redis is required for Redis integration") from exc
        self.client = redis.Redis.from_url(self.settings.redis_url, decode_responses=True, socket_timeout=5)
        await self.client.ping()

    async def close(self) -> None:
        if self.client is not None:
            await self.client.aclose()

    def key(self, *parts: str) -> str:
        return self.settings.redis_namespace + ":".join(str(part).strip(":") for part in parts)

    async def health(self) -> None:
        if self.client is None:
            raise RuntimeError("Redis client is not initialized")
        await self.client.ping()

    async def set_json(self, key: str, value: dict[str, Any], ttl_seconds: int | None = None) -> None:
        """Store application state in Redis without log redaction.

        Redis is an internal runtime store, not a log sink. Password reset state stores
        a one-way hash of the reset-token secret. Redacting this value before storage
        breaks /v1/password/reset because the later hash comparison can never match.
        Sensitive raw values must be avoided by callers before this method is called;
        this method preserves the internal values needed for correct application behavior.
        """
        if self.client is None:
            raise RuntimeError("Redis client is not initialized")
        await self.client.set(
            key,
            json.dumps(value, default=str),
            ex=ttl_seconds or self.settings.redis_cache_ttl_seconds,
        )

    async def get_json(self, key: str) -> dict[str, Any] | None:
        if self.client is None:
            raise RuntimeError("Redis client is not initialized")
        raw = await self.client.get(key)
        return json.loads(raw) if raw else None

    async def set_value(self, key: str, value: str, ttl_seconds: int) -> None:
        if self.client is None:
            raise RuntimeError("Redis client is not initialized")
        await self.client.set(key, value, ex=ttl_seconds)

    async def get_value(self, key: str) -> str | None:
        if self.client is None:
            raise RuntimeError("Redis client is not initialized")
        return await self.client.get(key)

    async def delete(self, *keys: str) -> None:
        if self.client is None:
            raise RuntimeError("Redis client is not initialized")
        if keys:
            await self.client.delete(*keys)

    async def exists(self, key: str) -> bool:
        if self.client is None:
            raise RuntimeError("Redis client is not initialized")
        return bool(await self.client.exists(key))


def _instrument_redis_methods() -> None:
    from app.observability.apm import apm_span

    for method_name in ["connect", "health", "set_json", "get_json", "set_value", "get_value", "delete", "exists"]:
        original = getattr(RedisClient, method_name)
        if getattr(original, "_apm_instrumented", False):
            continue

        async def wrapped(self, *args, __original=original, __name=method_name, **kwargs):
            async with apm_span(f"Redis {__name}", "cache.redis", labels={"db_system": "redis"}):
                return await __original(self, *args, **kwargs)

        wrapped.__name__ = original.__name__
        wrapped.__doc__ = original.__doc__
        wrapped._apm_instrumented = True
        setattr(RedisClient, method_name, wrapped)


_instrument_redis_methods()

