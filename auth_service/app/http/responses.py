from __future__ import annotations

import json
from typing import Any

from fastapi import Request
from starlette.responses import JSONResponse

from app.utils.time import iso_now


class PrettyJSONResponse(JSONResponse):
    media_type = "application/json"

    def render(self, content: Any) -> bytes:
        return (json.dumps(content, ensure_ascii=False, allow_nan=False, indent=2, default=str) + "\n").encode("utf-8")


def get_request_id(request: Request | None) -> str:
    return getattr(request.state, "request_id", None) if request else ""


def get_trace_id(request: Request | None) -> str:
    return getattr(request.state, "trace_id", None) if request else ""


def success_envelope(message: str, data: Any, request: Request | None = None) -> dict[str, Any]:
    return {
        "status": "ok",
        "message": message,
        "data": data,
        "request_id": get_request_id(request),
        "trace_id": get_trace_id(request),
        "timestamp": iso_now(),
    }


def error_envelope(
    message: str,
    error_code: str,
    request: Request | None = None,
    details: dict[str, Any] | None = None,
    path: str | None = None,
) -> dict[str, Any]:
    return {
        "status": "error",
        "message": message,
        "error_code": error_code,
        "details": details or {},
        "path": path or (request.url.path if request else ""),
        "request_id": get_request_id(request),
        "trace_id": get_trace_id(request),
        "timestamp": iso_now(),
    }
