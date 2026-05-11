from __future__ import annotations

import asyncio
import logging
import os
import time
import urllib.request
from contextlib import asynccontextmanager
from typing import Any, AsyncIterator

from app.config import Settings

logger = logging.getLogger("app.apm")

_elasticapm = None
_client = None
_settings: Settings | None = None


def _safe_import_elasticapm():
    global _elasticapm
    if _elasticapm is not None:
        return _elasticapm
    import elasticapm

    _elasticapm = elasticapm
    return elasticapm


def _sanitize_fields() -> tuple[str, ...]:
    return (
        "password",
        "passwd",
        "pwd",
        "password_hash",
        "secret",
        "*key",
        "*token*",
        "access_token",
        "refresh_token",
        "authorization",
        "cookie",
        "set-cookie",
        "jwt",
        "session",
        "credit",
        "card",
    )


def _export_env(settings: Settings) -> None:
    os.environ.setdefault("ELASTIC_APM_SERVICE_NAME", settings.service_name)
    os.environ.setdefault("ELASTIC_APM_SERVER_URL", settings.apm_server_url)
    os.environ.setdefault("ELASTIC_APM_SECRET_TOKEN", settings.apm_secret_token)
    os.environ.setdefault("ELASTIC_APM_ENVIRONMENT", settings.environment)
    os.environ.setdefault("ELASTIC_APM_TRANSACTION_SAMPLE_RATE", str(settings.apm_transaction_sample_rate))
    os.environ.setdefault("ELASTIC_APM_CAPTURE_BODY", settings.apm_capture_body)
    os.environ.setdefault("ELASTIC_APM_METRICS_INTERVAL", "30s")
    os.environ.setdefault("ELASTIC_APM_CENTRAL_CONFIG", "false")
    os.environ.setdefault("ELASTIC_APM_VERIFY_SERVER_CERT", "false")


def _get_client():
    return _client


def _get_elasticapm():
    try:
        return _safe_import_elasticapm()
    except Exception:
        return None


def _current_transaction_id(elasticapm=None) -> str | None:
    elasticapm = elasticapm or _get_elasticapm()
    if elasticapm is None:
        return None
    try:
        return elasticapm.get_transaction_id()
    except Exception:
        return None


def _http_result(status_code: int) -> str:
    return f"HTTP {status_code // 100}xx"


def _outcome(status_code: int) -> str:
    return "failure" if status_code >= 500 else "success"


def _label_safe(elasticapm, labels: dict[str, Any]) -> None:
    """Attach labels only when an APM transaction is active.

    The Elastic Python agent warns when labels are added without a transaction.
    Startup checks and background probes can legitimately run outside request
    transactions, so this guard keeps logs clean while still adding rich labels
    to real request/background transactions.
    """
    if not labels or _current_transaction_id(elasticapm) is None:
        return
    try:
        elasticapm.label(**{k: ("unknown" if v is None else str(v)) for k, v in labels.items()})
    except Exception:
        pass


class ApmClient:
    """Elastic APM facade used by HTTP middleware and infrastructure adapters."""

    def __init__(self, settings: Settings, client=None):
        self.settings = settings
        self.client = client
        self.elasticapm = None

    async def connect(self) -> None:
        global _client, _settings
        try:
            elasticapm = _safe_import_elasticapm()
        except ImportError as exc:
            raise RuntimeError("elastic-apm is required for APM integration") from exc

        _export_env(self.settings)
        self.elasticapm = elasticapm
        elasticapm.instrument()

        if self.client is None:
            self.client = elasticapm.Client(
                service_name=self.settings.service_name,
                server_url=self.settings.apm_server_url,
                secret_token=self.settings.apm_secret_token,
                environment=self.settings.environment,
                transaction_sample_rate=self.settings.apm_transaction_sample_rate,
                capture_body=self.settings.apm_capture_body,
                sanitize_field_names=_sanitize_fields(),
                metrics_interval="30s",
                central_config=False,
                verify_server_cert=False,
            )
        _client = self.client
        _settings = self.settings
        await self.health()
        self.capture_startup_transaction("application.startup")

    def capture_startup_transaction(self, name: str) -> None:
        if self.client is None or self.elasticapm is None:
            return
        try:
            self.client.begin_transaction("startup")
            _label_safe(
                self.elasticapm,
                {
                    "service": self.settings.service_name,
                    "environment": self.settings.environment,
                    "tenant": self.settings.tenant,
                },
            )
            self.client.end_transaction(name, "success")
            self.flush()
        except Exception as exc:  # pragma: no cover - best effort observability
            logger.debug("APM startup transaction skipped: %s", exc)

    def begin_request(self, request) -> dict[str, Any] | None:
        if self.client is None or self.elasticapm is None:
            return None
        state: dict[str, Any] = {"started": time.perf_counter(), "owns_transaction": False}
        try:
            # If the official Starlette middleware already created the transaction,
            # enrich it instead of starting a nested or conflicting transaction.
            if _current_transaction_id(self.elasticapm) is None:
                self.client.begin_transaction("request")
                state["owns_transaction"] = True
            self.elasticapm.set_transaction_name(f"{request.method} {request.url.path}")
            self.elasticapm.set_custom_context(
                {
                    "request_id": getattr(request.state, "request_id", None),
                    "trace_id": getattr(request.state, "trace_id", None),
                    "correlation_id": getattr(request.state, "correlation_id", None),
                    "tenant": self.settings.tenant,
                    "client_ip": request.client.host if request.client else None,
                    "user_agent": request.headers.get("user-agent"),
                }
            )
            _label_safe(
                self.elasticapm,
                {
                    "service": self.settings.service_name,
                    "environment": self.settings.environment,
                    "tenant": self.settings.tenant,
                    "request_id": getattr(request.state, "request_id", None) or "unknown",
                    "correlation_id": getattr(request.state, "correlation_id", None) or "unknown",
                    "http_method": request.method,
                    "http_route": request.url.path,
                },
            )
            return state
        except Exception as exc:  # pragma: no cover - best effort observability
            logger.debug("APM request transaction start skipped: %s", exc)
            return None

    def end_request(self, request, status_code: int, state: dict[str, Any] | None = None, exc: BaseException | None = None) -> None:
        if self.client is None or self.elasticapm is None or state is None:
            return
        try:
            route = getattr(request.scope.get("route"), "path", None) or request.url.path
            transaction_name = f"{request.method} {route}"
            user_id = getattr(request.state, "user_id", None)
            actor_id = getattr(request.state, "actor_id", None)
            if user_id:
                self.elasticapm.set_user_context(username=str(user_id), user_id=str(user_id))
            self.elasticapm.set_custom_context(
                {
                    "request_id": getattr(request.state, "request_id", None),
                    "trace_id": getattr(request.state, "trace_id", None),
                    "correlation_id": getattr(request.state, "correlation_id", None),
                    "actor_id": actor_id,
                    "duration_ms": round((time.perf_counter() - float(state.get("started", time.perf_counter()))) * 1000, 3),
                    "route": route,
                }
            )
            if exc is not None:
                self.client.capture_exception()
            self.elasticapm.set_transaction_name(transaction_name)
            self.elasticapm.set_transaction_result(_http_result(status_code))
            self.elasticapm.set_transaction_outcome(_outcome(status_code))
            if state.get("owns_transaction"):
                self.client.end_transaction(transaction_name, _http_result(status_code))
            # Flush quickly so local validation in Kibana does not need to wait for
            # the background sender's default interval. The official middleware can
            # still end its own transaction after this method returns.
            self.flush()
        except Exception as apm_exc:  # pragma: no cover - best effort observability
            logger.debug("APM request transaction end skipped: %s", apm_exc)

    @asynccontextmanager
    async def span(self, name: str, span_type: str = "app", labels: dict[str, Any] | None = None) -> AsyncIterator[None]:
        async with apm_span(name, span_type=span_type, labels=labels):
            yield

    async def health(self) -> None:
        def probe() -> None:
            request = urllib.request.Request(
                self.settings.apm_server_url,
                headers={"Authorization": f"Bearer {self.settings.apm_secret_token}"},
            )
            try:
                urllib.request.urlopen(request, timeout=3).read(64)
            except Exception as exc:
                # Elastic APM root may return HTTP errors while the server is reachable.
                if "HTTP Error" not in str(exc):
                    raise
        await asyncio.to_thread(probe)

    def capture_exception(self, exc: BaseException | None = None) -> None:
        if self.client is not None:
            try:
                self.client.capture_exception()
                self.flush()
            except Exception:
                pass

    def current_ids(self) -> tuple[str | None, str | None]:
        if self.elasticapm is None:
            return None, None
        try:
            return self.elasticapm.get_trace_id(), self.elasticapm.get_transaction_id()
        except Exception:
            return None, None

    def flush(self) -> None:
        if self.client is None:
            return
        try:
            transport = getattr(self.client, "_transport", None) or getattr(self.client, "transport", None)
            if transport is not None and hasattr(transport, "flush"):
                transport.flush()
        except Exception:
            pass

    async def close(self) -> None:
        if self.client is not None:
            self.flush()
            self.client.close()


@asynccontextmanager
async def apm_span(name: str, span_type: str = "app", labels: dict[str, Any] | None = None) -> AsyncIterator[None]:
    elasticapm = _get_elasticapm()
    if elasticapm is None:
        yield
        return
    try:
        with elasticapm.capture_span(name, span_type):
            _label_safe(elasticapm, labels or {})
            yield
    except Exception:
        raise


@asynccontextmanager
async def apm_background_transaction(name: str, transaction_type: str = "background") -> AsyncIterator[None]:
    client = _get_client()
    elasticapm = _get_elasticapm()
    if client is None or elasticapm is None:
        yield
        return
    try:
        client.begin_transaction(transaction_type)
        elasticapm.set_transaction_name(name)
        _label_safe(elasticapm, {"transaction_kind": "background"})
        yield
        elasticapm.set_transaction_result("success")
        elasticapm.set_transaction_outcome("success")
        client.end_transaction(name, "success")
    except Exception:
        try:
            elasticapm.set_transaction_result("failure")
            elasticapm.set_transaction_outcome("failure")
            client.capture_exception()
            client.end_transaction(name, "failure")
        finally:
            raise
    finally:
        try:
            transport = getattr(client, "_transport", None) or getattr(client, "transport", None)
            if transport is not None and hasattr(transport, "flush"):
                transport.flush()
        except Exception:
            pass


def capture_apm_exception(exc: BaseException | None = None) -> None:
    client = _get_client()
    if client is not None:
        try:
            client.capture_exception()
        except Exception:
            pass


def install_elastic_apm_middleware(app, settings: Settings) -> None:
    """Install the official Starlette middleware and expose the same client to app code."""
    if getattr(app.state, "elastic_apm_installed", False):
        return
    try:
        elasticapm = _safe_import_elasticapm()
        from elasticapm.contrib.starlette import ElasticAPM
    except ImportError:
        return

    _export_env(settings)
    client = elasticapm.Client(
        service_name=settings.service_name,
        server_url=settings.apm_server_url,
        secret_token=settings.apm_secret_token,
        environment=settings.environment,
        transaction_sample_rate=settings.apm_transaction_sample_rate,
        capture_body=settings.apm_capture_body,
        sanitize_field_names=_sanitize_fields(),
        metrics_interval="30s",
        central_config=False,
        verify_server_cert=False,
    )
    elasticapm.instrument()
    app.add_middleware(ElasticAPM, client=client)
    app.state.elastic_apm_middleware_client = client
    app.state.elastic_apm_installed = True

