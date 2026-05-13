from __future__ import annotations

from typing import Any

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.http.responses import PrettyJSONResponse, error_envelope


class AppError(Exception):
    def __init__(self, status_code: int, message: str, error_code: str, details: dict[str, Any] | None = None):
        self.status_code = status_code
        self.message = message
        self.error_code = error_code
        self.details = details or {}
        super().__init__(message)


def unauthorized(message: str = "Authentication required", error_code: str = "UNAUTHORIZED") -> AppError:
    return AppError(401, message, error_code)


def forbidden(message: str = "Forbidden", error_code: str = "FORBIDDEN") -> AppError:
    return AppError(403, message, error_code)


def not_found(message: str = "Resource not found", error_code: str = "NOT_FOUND") -> AppError:
    return AppError(404, message, error_code)


def conflict(message: str, error_code: str = "CONFLICT", details: dict[str, Any] | None = None) -> AppError:
    return AppError(409, message, error_code, details)


def bad_request(message: str, error_code: str = "BAD_REQUEST", details: dict[str, Any] | None = None) -> AppError:
    return AppError(400, message, error_code, details)


async def app_error_handler(request: Request, exc: AppError) -> PrettyJSONResponse:
    return PrettyJSONResponse(error_envelope(exc.message, exc.error_code, request, exc.details), status_code=exc.status_code)


async def http_exception_handler(request: Request, exc: StarletteHTTPException) -> PrettyJSONResponse:
    code = "NOT_FOUND" if exc.status_code == 404 else "HTTP_ERROR"
    if exc.status_code == 401:
        code = "UNAUTHORIZED"
    elif exc.status_code == 403:
        code = "FORBIDDEN"
    return PrettyJSONResponse(error_envelope(str(exc.detail), code, request), status_code=exc.status_code)


async def validation_exception_handler(request: Request, exc: RequestValidationError) -> PrettyJSONResponse:
    details = {"errors": exc.errors()}
    return PrettyJSONResponse(error_envelope("Validation failed", "VALIDATION_ERROR", request, details), status_code=422)


async def unhandled_exception_handler(request: Request, exc: Exception) -> PrettyJSONResponse:
    return PrettyJSONResponse(error_envelope("Internal server error", "INTERNAL_SERVER_ERROR", request), status_code=500)
