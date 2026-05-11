from __future__ import annotations

from typing import Annotated, Any

import jwt
from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.http.errors import forbidden, unauthorized
from app.security.tokens import decode_access_token

bearer_scheme = HTTPBearer(auto_error=False, scheme_name="bearerAuth")


async def current_claims(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> dict[str, Any]:
    if credentials is None or credentials.scheme.lower() != "bearer" or not credentials.credentials:
        raise unauthorized()
    settings = request.app.state.settings
    try:
        claims = decode_access_token(settings, credentials.credentials)
    except jwt.ExpiredSignatureError as exc:
        raise unauthorized("Token expired", "TOKEN_EXPIRED") from exc
    except jwt.InvalidTokenError as exc:
        raise unauthorized("Invalid token", "INVALID_TOKEN") from exc

    if settings.security_require_tenant_match and claims.get("tenant") != settings.tenant:
        raise forbidden("Token tenant does not match service tenant", "TENANT_MISMATCH")
    if claims.get("role") not in settings.allowed_roles:
        raise forbidden("Token role is not allowed", "ROLE_NOT_ALLOWED")
    if claims.get("admin_status") not in settings.allowed_admin_statuses:
        raise forbidden("Token admin_status is not allowed", "ADMIN_STATUS_NOT_ALLOWED")

    auth_service = getattr(request.app.state, "auth_service", None)
    if auth_service is not None:
        await auth_service.ensure_token_session_active(claims)
    request.state.user_id = claims.get("sub")
    request.state.actor_id = claims.get("sub")
    return claims


async def approved_admin_claims(claims: Annotated[dict[str, Any], Depends(current_claims)]) -> dict[str, Any]:
    if claims.get("role") != "admin" or claims.get("admin_status") != "approved" or claims.get("status", "active") != "active":
        raise forbidden("Approved admin access required", "ADMIN_ACCESS_REQUIRED")
    return claims
