from __future__ import annotations

import logging
import time
from typing import Awaitable, Callable

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

from app.utils.ids import new_request_id, new_trace_id

logger = logging.getLogger("app.request")
PUBLIC_NOISE_PATHS = {"/hello", "/health", "/docs"}


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: Callable[[Request], Awaitable[Response]]) -> Response:
        request.state.request_id = request.headers.get("X-Request-ID") or new_request_id()
        request.state.trace_id = request.headers.get("X-Trace-ID") or new_trace_id()
        request.state.correlation_id = request.headers.get("X-Correlation-ID") or request.state.request_id
        request.state.user_id = None
        request.state.actor_id = None
        started = time.perf_counter()
        response: Response | None = None
        exc: BaseException | None = None
        apm = getattr(request.app.state, "apm", None)
        apm_state = apm.begin_request(request) if apm is not None else None
        try:
            response = await call_next(request)
            return response
        except BaseException as caught:
            exc = caught
            if apm is not None:
                apm.capture_exception(caught)
            raise
        finally:
            duration_ms = round((time.perf_counter() - started) * 1000, 3)
            status_code = response.status_code if response is not None else 500
            if response is not None:
                response.headers["X-Request-ID"] = request.state.request_id
                response.headers["X-Trace-ID"] = request.state.trace_id
                response.headers["X-Correlation-ID"] = request.state.correlation_id
            apm_trace_id = None
            apm_transaction_id = None
            if apm is not None:
                # Read IDs before ending a fallback transaction. If the official
                # Elastic middleware owns the transaction, these IDs remain active
                # for correlated logs and Mongo log documents.
                apm_trace_id, apm_transaction_id = apm.current_ids()
                apm.end_request(request, status_code, state=apm_state, exc=exc)
                if apm_trace_id is None or apm_transaction_id is None:
                    fallback_trace_id, fallback_transaction_id = apm.current_ids()
                    apm_trace_id = apm_trace_id or fallback_trace_id
                    apm_transaction_id = apm_transaction_id or fallback_transaction_id
            if not (request.url.path in PUBLIC_NOISE_PATHS and status_code < 400):
                logger.info(
                    "request completed",
                    extra={
                        "event": "http.request.completed",
                        "request_id": request.state.request_id,
                        "trace_id": request.state.trace_id,
                        "correlation_id": request.state.correlation_id,
                        "user_id": getattr(request.state, "user_id", None),
                        "actor_id": getattr(request.state, "actor_id", None),
                        "method": request.method,
                        "path": request.url.path,
                        "status_code": status_code,
                        "duration_ms": duration_ms,
                        "client_ip": request.client.host if request.client else None,
                        "user_agent": request.headers.get("user-agent"),
                        "apm_trace_id": apm_trace_id,
                        "apm_transaction_id": apm_transaction_id,
                    },
                )
                mongo = getattr(request.app.state, "mongo_logger", None)
                if mongo is not None:
                    mongo.write_background(
                        level="INFO" if status_code < 400 else "WARN",
                        event="http.request.completed",
                        message="request completed",
                        request_id=request.state.request_id,
                        trace_id=request.state.trace_id,
                        correlation_id=request.state.correlation_id,
                        user_id=getattr(request.state, "user_id", None),
                        actor_id=getattr(request.state, "actor_id", None),
                        method=request.method,
                        path=request.url.path,
                        status_code=status_code,
                        duration_ms=duration_ms,
                        client_ip=request.client.host if request.client else None,
                        user_agent=request.headers.get("user-agent"),
                        apm_trace_id=apm_trace_id,
                        apm_transaction_id=apm_transaction_id,
                    )


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: Callable[[Request], Awaitable[Response]]) -> Response:
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault("Cache-Control", "no-store")
        return response

