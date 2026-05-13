from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.config import load_settings
from app.health.service import HealthService
from app.http.errors import AppError, app_error_handler, http_exception_handler, unhandled_exception_handler, validation_exception_handler
from app.http.middleware import RequestContextMiddleware, SecurityHeadersMiddleware
from app.http.responses import PrettyJSONResponse
from app.http.routes.admin import router as admin_router
from app.http.routes.auth import router as auth_router
from app.http.routes.system import router as system_router
from app.kafka.client import InboxConsumer, KafkaClient, OutboxPublisher
from app.logging.logger import configure_logging
from app.logging.mongo import MongoLogWriter
from app.observability.apm import ApmClient, install_elastic_apm_middleware
from app.observability.elastic import ElasticsearchClient
from app.persistence.postgres import PostgresRepository
from app.redis.client import RedisClient
from app.s3.client import S3Client
from app.services.auth import AuthService
from app.services.bootstrap import bootstrap_default_admin

logger = logging.getLogger("app.main")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = app.state.settings
    configure_logging(settings)
    logger.info(
        "configuration validated",
        extra={
            "event": "application.config.validated",
            "extra": {"service": settings.service_name, "environment": settings.environment},
        },
    )

    postgres = PostgresRepository(settings)
    redis_client = RedisClient(settings)
    kafka = KafkaClient(settings)
    s3 = S3Client(settings)
    mongo_logger = MongoLogWriter(settings)
    apm = ApmClient(settings, getattr(app.state, "elastic_apm_middleware_client", None))
    elasticsearch = ElasticsearchClient(settings)

    outbox = None
    inbox = None
    try:
        await apm.connect()
        await postgres.connect()
        await postgres.migrate()
        await redis_client.connect()
        await kafka.connect()
        await s3.connect()
        await mongo_logger.connect()
        await elasticsearch.connect()
        await bootstrap_default_admin(postgres, settings)

        app.state.postgres = postgres
        app.state.redis = redis_client
        app.state.kafka = kafka
        app.state.s3 = s3
        app.state.mongo_logger = mongo_logger
        app.state.apm = apm
        app.state.elasticsearch = elasticsearch
        app.state.auth_service = AuthService(settings, postgres, redis_client, kafka, s3)
        app.state.health_service = HealthService(
            settings,
            {
                "postgres": postgres.health,
                "redis": redis_client.health,
                "kafka": kafka.health,
                "s3": s3.health,
                "mongodb": mongo_logger.health,
                "apm": apm.health,
                "elasticsearch": elasticsearch.health,
            },
        )

        outbox = OutboxPublisher(postgres, kafka)
        inbox = InboxConsumer(postgres, kafka)
        outbox.start()
        inbox.start()
        app.state.outbox_publisher = outbox
        app.state.inbox_consumer = inbox
        logger.info("application started", extra={"event": "application.started"})
        yield
    finally:
        logger.info("application shutdown started", extra={"event": "application.shutdown.started"})
        if outbox:
            await outbox.stop()
        if inbox:
            await inbox.stop()
        await elasticsearch.close()
        await apm.close()
        await mongo_logger.close()
        await s3.close()
        await kafka.close()
        await redis_client.close()
        await postgres.close()
        logger.info("application shutdown completed", extra={"event": "application.shutdown.completed"})


def create_app(*, lifespan_enabled: bool = True) -> FastAPI:
    settings = load_settings()
    app = FastAPI(
        title="auth_service API",
        version=settings.version,
        default_response_class=PrettyJSONResponse,
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        lifespan=lifespan if lifespan_enabled else None,
        openapi_tags=[
            {
                "name": "system",
                "description": "Public service information. Only /hello, /health, and /docs are public system routes.",
            },
            {
                "name": "auth",
                "description": "Signup, signin, logout, refresh token, password, current-user, and token verification APIs.",
            },
            {
                "name": "admin",
                "description": "Approved-admin-only APIs for reviewing and deciding admin registration requests.",
            },
        ],
    )
    app.state.settings = settings

    if not lifespan_enabled:
        async def _ok():
            return None
        app.state.health_service = HealthService(
            settings,
            {
                "postgres": _ok,
                "redis": _ok,
                "kafka": _ok,
                "s3": _ok,
                "mongodb": _ok,
                "apm": _ok,
                "elasticsearch": _ok,
            },
        )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_allowed_origins,
        allow_methods=settings.cors_allowed_methods,
        allow_headers=settings.cors_allowed_headers,
        allow_credentials=settings.cors_allow_credentials,
        max_age=settings.cors_max_age_seconds,
    )
    app.add_middleware(SecurityHeadersMiddleware)
    app.add_middleware(RequestContextMiddleware)

    # Install the official Elastic APM Starlette middleware after the local
    # middleware stack is registered so APM sees full request transactions.
    # RequestContextMiddleware still enriches the active transaction with
    # request_id, trace_id, user_id and route metadata.
    if lifespan_enabled:
        install_elastic_apm_middleware(app, settings)

    app.add_exception_handler(AppError, app_error_handler)
    app.add_exception_handler(StarletteHTTPException, http_exception_handler)
    app.add_exception_handler(RequestValidationError, validation_exception_handler)
    app.add_exception_handler(Exception, unhandled_exception_handler)

    app.include_router(system_router)
    app.include_router(auth_router)
    app.include_router(admin_router)
    return app


app = create_app(lifespan_enabled=True)

