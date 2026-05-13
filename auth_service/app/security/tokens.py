from __future__ import annotations

import hashlib
import secrets
from datetime import timedelta
from typing import Any

import jwt

from app.config import Settings
from app.utils.ids import new_id
from app.utils.time import epoch_seconds, utc_now


def hash_opaque_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def new_password_reset_token() -> tuple[str, str]:
    token_id = new_id("prt")
    secret = secrets.token_urlsafe(48)
    return token_id, f"{token_id}.{secret}"


def split_password_reset_token(token: str) -> tuple[str, str]:
    token_id, sep, secret = token.partition(".")
    if not sep or not token_id or not secret:
        raise ValueError("invalid reset token")
    return token_id, secret


def build_access_claims(settings: Settings, user: dict[str, Any], jti: str) -> dict[str, Any]:
    now = utc_now()
    exp = now + timedelta(minutes=settings.access_token_expire_minutes)
    return {
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "sub": str(user["id"]),
        "jti": jti,
        "username": user["username"],
        "email": user["email"],
        "role": user["role"],
        "admin_status": user["admin_status"],
        "tenant": user["tenant"],
        "status": user.get("status", "active"),
        "iat": epoch_seconds(now),
        "nbf": epoch_seconds(now),
        "exp": epoch_seconds(exp),
    }


def encode_access_token(settings: Settings, claims: dict[str, Any]) -> str:
    return jwt.encode(claims, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(settings: Settings, token: str) -> dict[str, Any]:
    return jwt.decode(
        token,
        settings.jwt_secret,
        algorithms=[settings.jwt_algorithm],
        issuer=settings.jwt_issuer,
        audience=settings.jwt_audience,
        leeway=settings.jwt_leeway_seconds,
        options={"require": ["iss", "aud", "sub", "jti", "iat", "nbf", "exp"]},
    )
