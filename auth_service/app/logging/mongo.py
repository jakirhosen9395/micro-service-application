from __future__ import annotations

import asyncio
import logging
import socket
from typing import Any

from app.config import Settings
from app.observability.apm import apm_span, capture_apm_exception
from app.utils.redaction import redact
from app.utils.time import iso_now

logger = logging.getLogger("app.mongo_logging")


class MongoLogWriter:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.client = None
        self.collection = None
        self.host = socket.gethostname()

    async def connect(self) -> None:
        try:
            from motor.motor_asyncio import AsyncIOMotorClient
        except ImportError as exc:
            raise RuntimeError("motor is required for MongoDB structured logging") from exc
        async with apm_span("MongoDB connect", "db.mongodb", labels={"database": self.settings.mongo_database}):
            self.client = AsyncIOMotorClient(self.settings.mongodb_uri, serverSelectionTimeoutMS=5000)
            await self.client.admin.command("ping")
            self.collection = self.client[self.settings.mongo_database][self.settings.mongo_log_collection]
            await self.create_indexes()

    async def create_indexes(self) -> None:
        if self.collection is None:
            return
        async with apm_span("MongoDB create_indexes", "db.mongodb", labels={"collection": self.settings.mongo_log_collection}):
            await self.collection.create_index([("timestamp", -1)])
            await self.collection.create_index([("level", 1), ("timestamp", -1)])
            await self.collection.create_index([("event", 1), ("timestamp", -1)])
            await self.collection.create_index([("request_id", 1)])
            await self.collection.create_index([("trace_id", 1)])
            await self.collection.create_index([("user_id", 1), ("timestamp", -1)])
            await self.collection.create_index([("path", 1), ("status_code", 1), ("timestamp", -1)])
            await self.collection.create_index([("error_code", 1), ("timestamp", -1)])
            if self.settings.environment != "production":
                await self.collection.create_index([("timestamp", 1)], expireAfterSeconds=1209600)

    async def write(self, *, level: str, event: str, message: str, **fields: Any) -> None:
        if self.collection is None:
            return
        apm_trace_id = fields.pop("apm_trace_id", None)
        apm_transaction_id = fields.pop("apm_transaction_id", None)
        request_id = fields.pop("request_id", None)
        trace_id = fields.pop("trace_id", None)
        correlation_id = fields.pop("correlation_id", None)
        user_id = fields.pop("user_id", None)
        actor_id = fields.pop("actor_id", None)
        doc = {
            "timestamp": iso_now(),
            "level": level.upper(),
            "service": self.settings.service_name,
            "version": self.settings.version,
            "environment": self.settings.environment,
            "tenant": self.settings.tenant,
            "logger": fields.pop("logger", "app.request"),
            "event": event,
            "message": message,
            "request_id": request_id,
            "trace_id": trace_id,
            "correlation_id": correlation_id,
            "user_id": user_id,
            "actor_id": actor_id,
            "method": fields.pop("method", None),
            "path": fields.pop("path", None),
            "status_code": fields.pop("status_code", None),
            "duration_ms": fields.pop("duration_ms", None),
            "client_ip": fields.pop("client_ip", None),
            "user_agent": fields.pop("user_agent", None),
            "dependency": fields.pop("dependency", None),
            "error_code": fields.pop("error_code", None),
            "exception_class": fields.pop("exception_class", None),
            "exception_message": fields.pop("exception_message", None),
            "stack_trace": fields.pop("stack_trace", None),
            "host": self.host,
            # ECS-style fields help Kibana Logs correlate records when stdout or
            # Mongo-to-Elastic ingestion is configured by the platform.
            "trace.id": apm_trace_id or trace_id,
            "transaction.id": apm_transaction_id,
            "service.name": self.settings.service_name,
            "service.environment": self.settings.environment,
            "event.dataset": f"{self.settings.service_name}.application",
            "extra": fields,
        }
        async with apm_span("MongoDB log.insert", "db.mongodb", labels={"collection": self.settings.mongo_log_collection}):
            await self.collection.insert_one(redact(doc))

    def write_background(self, **kwargs: Any) -> None:
        try:
            asyncio.create_task(self.write(**kwargs))
        except RuntimeError:
            logger.debug("MongoDB log write skipped outside event loop")
        except Exception as exc:
            capture_apm_exception(exc)

    async def health(self) -> None:
        if self.client is None:
            raise RuntimeError("MongoDB client is not initialized")
        async with apm_span("MongoDB ping", "db.mongodb", labels={"database": self.settings.mongo_database}):
            await self.client.admin.command("ping")

    async def close(self) -> None:
        if self.client is not None:
            self.client.close()
