from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Request

from app.domain.schemas import (
    AdminRegisterRequest,
    ChangePasswordRequest,
    ForgotPasswordRequest,
    RefreshTokenRequest,
    ResetPasswordRequest,
    SigninRequest,
    SignupRequest,
)
from app.http.responses import success_envelope
from app.security.dependencies import current_claims

router = APIRouter(prefix="/v1", tags=["auth"])


def ok_example(message: str, data: dict) -> dict:
    return {
        "status": "ok",
        "message": message,
        "data": data,
        "request_id": "req_example",
        "trace_id": "trc_example",
        "timestamp": "2026-05-10T00:00:00.000Z",
    }


def err_example(path: str, message: str, error_code: str) -> dict:
    return {
        "status": "error",
        "message": message,
        "error_code": error_code,
        "details": {},
        "path": path,
        "request_id": "req_example",
        "trace_id": "trc_example",
        "timestamp": "2026-05-10T00:00:00.000Z",
    }


USER_EXAMPLE = {
    "id": "usr_example",
    "username": "jakir",
    "email": "jakir@example.com",
    "full_name": "Md Jakir Hosen",
    "birthdate": "1998-05-20",
    "gender": "male",
    "role": "user",
    "admin_status": "not_requested",
    "tenant": "dev",
    "status": "active",
    "email_verified": False,
}
TOKENS_EXAMPLE = {
    "access_token": "eyJhbGciOiJIUzI1NiIs...",
    "refresh_token": "refresh-token-value",
    "token_type": "Bearer",
    "expires_in": 900,
}
VALIDATION_RESPONSE = {"description": "Payload validation failed"}
UNAUTHORIZED_RESPONSE = {
    "description": "Missing, invalid, expired, or revoked JWT",
    "content": {"application/json": {"example": err_example("/v1/me", "Authentication required", "UNAUTHORIZED")}},
}
FORBIDDEN_RESPONSE = {
    "description": "Valid JWT without sufficient permissions",
    "content": {"application/json": {"example": err_example("/v1/admin/requests", "Approved admin access required", "ADMIN_ACCESS_REQUIRED")}},
}


@router.post(
    "/signup",
    summary="Create a normal user or submit admin signup request",
    description="""
Creates a normal user when `account_type` is omitted or set to `user`.

Successful normal-user behavior:
- hashes the password using Argon2
- stores the user in PostgreSQL
- creates an auth session
- stores Redis session cache
- writes an auth audit event into PostgreSQL
- writes a redacted S3 audit snapshot
- writes a Kafka outbox event
- returns safe user profile and token pair

Admin signup option:
- set `account_type` to `admin`
- provide `reason`
- the account is created as `role=admin` with `admin_status=pending`
- an approved admin must later approve it through `/v1/admin/requests/{user_id}/decision`
""",
    response_description="Safe user profile and tokens for normal signup; pending admin request for admin signup.",
    responses={
        200: {"description": "Signup succeeded", "content": {"application/json": {"example": ok_example("signup succeeded", {"user": USER_EXAMPLE, "tokens": TOKENS_EXAMPLE})}}},
        409: {"description": "Username or email already exists", "content": {"application/json": {"example": err_example("/v1/signup", "Username or email already exists", "USER_ALREADY_EXISTS")}}},
        422: VALIDATION_RESPONSE,
    },
)
async def signup(payload: SignupRequest, request: Request):
    data = await request.app.state.auth_service.signup(payload, request)
    return success_envelope("signup succeeded", data, request)


@router.post(
    "/signin",
    summary="Sign in and receive JWT tokens",
    description="""
Validates username/email and password, updates failed-login count on failure, creates a new active session on success, stores Redis session cache, writes PostgreSQL/S3 audit data, creates Kafka outbox event, and returns an access token plus refresh token.

Copy `data.tokens.access_token`, click Authorize, and paste `Bearer <access_token>`.
""",
    response_description="JWT access token, refresh token, and safe user profile.",
    responses={
        200: {"description": "Signin succeeded", "content": {"application/json": {"example": ok_example("signin succeeded", {"user": USER_EXAMPLE, "tokens": TOKENS_EXAMPLE})}}},
        401: {"description": "Invalid credentials", "content": {"application/json": {"example": err_example("/v1/signin", "Invalid username/email or password", "INVALID_CREDENTIALS")}}},
        403: {"description": "Inactive or suspended user", "content": {"application/json": {"example": err_example("/v1/signin", "User account is not active", "USER_NOT_ACTIVE")}}},
        422: VALIDATION_RESPONSE,
    },
)
async def signin(payload: SigninRequest, request: Request):
    data = await request.app.state.auth_service.signin(payload, request)
    return success_envelope("signin succeeded", data, request)


@router.post(
    "/login",
    summary="Compatibility alias for signin",
    description="Alias for `/v1/signin`. It validates credentials, records failed-login count on failure, and creates session/tokens on success.",
    response_description="JWT access token, refresh token, and safe user profile.",
    responses={200: {"description": "Login succeeded", "content": {"application/json": {"example": ok_example("signin succeeded", {"user": USER_EXAMPLE, "tokens": TOKENS_EXAMPLE})}}}, 401: {"description": "Invalid credentials"}, 422: VALIDATION_RESPONSE},
)
async def login(payload: SigninRequest, request: Request):
    data = await request.app.state.auth_service.signin(payload, request)
    return success_envelope("signin succeeded", data, request)


@router.post(
    "/logout",
    summary="Revoke current session and blacklist current access token",
    description="Requires bearer token. Revokes current PostgreSQL session, blacklists current JWT `jti` in Redis, emits `auth.user.logged_out`, and returns success even though the token becomes unusable after logout.",
    response_description="Logout success marker.",
    responses={200: {"description": "Logout succeeded", "content": {"application/json": {"example": ok_example("logout succeeded", {"revoked": True})}}}, 401: UNAUTHORIZED_RESPONSE, 403: FORBIDDEN_RESPONSE},
)
async def logout(claims: Annotated[dict, Depends(current_claims)], request: Request):
    data = await request.app.state.auth_service.logout(claims, request)
    return success_envelope("logout succeeded", data, request)


@router.post(
    "/token/refresh",
    summary="Rotate refresh token and issue new access token",
    description="Accepts refresh token, validates its hash, rotates refresh token, writes Redis blacklist for old `jti`, creates a new access token, updates session state, and emits `auth.token.refreshed`.",
    response_description="New token pair and safe user profile.",
    responses={200: {"description": "Token refreshed", "content": {"application/json": {"example": ok_example("token refreshed", {"user": USER_EXAMPLE, "tokens": TOKENS_EXAMPLE})}}}, 401: {"description": "Invalid refresh token"}, 422: VALIDATION_RESPONSE},
)
async def refresh(payload: RefreshTokenRequest, request: Request):
    data = await request.app.state.auth_service.refresh(payload, request)
    return success_envelope("token refreshed", data, request)


@router.get(
    "/me",
    summary="Get current safe user profile",
    description="Requires bearer token. Returns current safe user profile and never returns password hash, raw refresh token, or access token.",
    response_description="Safe current-user profile.",
    responses={200: {"description": "Current user loaded", "content": {"application/json": {"example": ok_example("current user loaded", USER_EXAMPLE)}}}, 401: UNAUTHORIZED_RESPONSE, 403: FORBIDDEN_RESPONSE},
)
async def me(claims: Annotated[dict, Depends(current_claims)], request: Request):
    data = await request.app.state.auth_service.me(claims)
    return success_envelope("current user loaded", data, request)


@router.get(
    "/verify",
    summary="Verify JWT and active session",
    description="Requires bearer token. Verifies token claims and active session state. Useful for humans and internal service JWT compatibility testing.",
    response_description="Token active state, claims, and safe user profile.",
    responses={200: {"description": "Token verified", "content": {"application/json": {"example": ok_example("token verified", {"active": True, "claims": {"sub": "usr_example", "role": "user"}, "user": USER_EXAMPLE})}}}, 401: UNAUTHORIZED_RESPONSE, 403: FORBIDDEN_RESPONSE},
)
async def verify(claims: Annotated[dict, Depends(current_claims)], request: Request):
    data = await request.app.state.auth_service.verify(claims)
    return success_envelope("token verified", data, request)


@router.post(
    "/password/forgot",
    summary="Start password reset flow",
    description="Accepts email, username, identifier, or username_or_email. Always returns accepted to avoid account enumeration. In non-production, if the user exists, response includes `reset_token` for local testing; production must not expose reset tokens.",
    response_description="Accepted marker and optional non-production reset token.",
    responses={200: {"description": "Password reset flow accepted", "content": {"application/json": {"example": ok_example("password reset flow accepted", {"accepted": True, "reset_token": "pwreset_token_for_non_production_only"})}}}, 422: VALIDATION_RESPONSE},
)
async def forgot_password(payload: ForgotPasswordRequest, request: Request):
    data = await request.app.state.auth_service.forgot_password(payload, request)
    return success_envelope("password reset flow accepted", data, request)


@router.post(
    "/password/reset",
    summary="Reset password using reset token",
    description="Accepts `reset_token` or `token` plus new password. Validates Redis reset-token state, updates PostgreSQL password hash, emits `auth.password.reset_completed`, and deletes the Redis reset token.",
    response_description="Password reset success marker.",
    responses={200: {"description": "Password reset completed", "content": {"application/json": {"example": ok_example("password reset completed", {"password_reset": True})}}}, 400: {"description": "Invalid reset token", "content": {"application/json": {"example": err_example("/v1/password/reset", "Invalid reset token", "INVALID_RESET_TOKEN")}}}, 422: VALIDATION_RESPONSE},
)
async def reset_password(payload: ResetPasswordRequest, request: Request):
    data = await request.app.state.auth_service.reset_password(payload, request)
    return success_envelope("password reset completed", data, request)


@router.post(
    "/password/change",
    summary="Change password for authenticated user",
    description="Requires bearer token. Validates current password, applies password policy, updates Argon2 password hash, revokes existing sessions, blacklists current JWT `jti`, and emits `auth.password.changed`.",
    response_description="Password changed success marker.",
    responses={200: {"description": "Password changed", "content": {"application/json": {"example": ok_example("password changed", {"password_changed": True})}}}, 401: UNAUTHORIZED_RESPONSE, 403: FORBIDDEN_RESPONSE, 422: VALIDATION_RESPONSE},
)
async def change_password(payload: ChangePasswordRequest, claims: Annotated[dict, Depends(current_claims)], request: Request):
    data = await request.app.state.auth_service.change_password(payload, claims, request)
    return success_envelope("password changed", data, request)


@router.post(
    "/admin/register",
    summary="Request admin account registration",
    description="Creates an admin registration request. The user is not approved admin immediately; `admin_status` becomes `pending` and an existing approved admin must approve later.",
    response_description="Pending admin registration request.",
    responses={200: {"description": "Admin registration requested", "content": {"application/json": {"example": ok_example("admin registration requested", {"user": {**USER_EXAMPLE, "role": "admin", "admin_status": "pending"}, "request_status": "pending"})}}}, 409: {"description": "Username or email already exists"}, 422: VALIDATION_RESPONSE},
)
async def admin_register(payload: AdminRegisterRequest, request: Request):
    data = await request.app.state.auth_service.admin_register(payload, request)
    return success_envelope("admin registration requested", data, request)
