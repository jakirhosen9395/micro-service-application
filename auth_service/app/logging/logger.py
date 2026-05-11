from __future__ import annotations

import json
import logging
import socket
import sys
from typing import Any

from app.config import Settings
from app.utils.redaction import redact
from app.utils.time import iso_now


def _current_apm_ids() -> tuple[str | None, str | None]:
    try:
        import elasticapm
        return elasticapm.get_trace_id(), elasticapm.get_transaction_id()
    except Exception:
        return None, None


class PrettyJsonFormatter(logging.Formatter):
    def __init__(self, settings: Settings):
        super().__init__()
        self.settings = settings
        self.host = socket.gethostname()

    def format(self, record: logging.LogRecord) -> str:
        apm_trace_id, apm_transaction_id = _current_apm_ids()
        doc: dict[str, Any] = {
            "timestamp": iso_now(),
            "level": record.levelname,
            "service": self.settings.service_name,
            "version": self.settings.version,
            "environment": self.settings.environment,
            "tenant": self.settings.tenant,
            "logger": record.name,
            "event": getattr(record, "event", None),
            "message": record.getMessage(),
            "request_id": getattr(record, "request_id", None),
            "trace_id": getattr(record, "trace_id", None),
            "correlation_id": getattr(record, "correlation_id", None),
            "user_id": getattr(record, "user_id", None),
            "actor_id": getattr(record, "actor_id", None),
            "method": getattr(record, "method", None),
            "path": getattr(record, "path", None),
            "status_code": getattr(record, "status_code", None),
            "duration_ms": getattr(record, "duration_ms", None),
            "client_ip": getattr(record, "client_ip", None),
            "user_agent": getattr(record, "user_agent", None),
            "dependency": getattr(record, "dependency", None),
            "error_code": getattr(record, "error_code", None),
            "exception_class": record.exc_info[0].__name__ if record.exc_info else None,
            "exception_message": str(record.exc_info[1]) if record.exc_info else None,
            "stack_trace": self.formatException(record.exc_info) if record.exc_info and record.levelno >= logging.ERROR else None,
            "host": self.host,
            "trace.id": apm_trace_id or getattr(record, "trace_id", None),
            "transaction.id": apm_transaction_id,
            "service.name": self.settings.service_name,
            "service.environment": self.settings.environment,
            "event.dataset": f"{self.settings.service_name}.application",
            "extra": redact(getattr(record, "extra", {}) or {}),
        }
        return json.dumps(redact(doc), ensure_ascii=False, indent=2, default=str)


def configure_logging(settings: Settings) -> None:
    root = logging.getLogger()
    root.handlers.clear()
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(PrettyJsonFormatter(settings))
    root.addHandler(handler)
    root.setLevel(getattr(logging, settings.log_level.upper(), logging.INFO))
    logging.getLogger("uvicorn.access").disabled = True
    logging.getLogger("asyncio").setLevel(logging.WARNING)
    # Keep dependency failures visible, but suppress noisy normal client lifecycle logs.
    for noisy_logger in (
        "aiokafka",
        "aiokafka.consumer",
        "aiokafka.consumer.group_coordinator",
        "aiokafka.consumer.subscription_state",
        "aiokafka.conn",
        "elastic_transport.transport",
    ):
        logging.getLogger(noisy_logger).setLevel(logging.WARNING)


def log_event(logger: logging.Logger, level: int, message: str, event: str, **extra: Any) -> None:
    safe = redact(extra)
    logger.log(level, message, extra={"event": event, **safe})
