from __future__ import annotations

import re

from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

from app.config import Settings
from app.http.errors import bad_request

_hasher = PasswordHasher()


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _hasher.verify(password_hash, password)
    except VerifyMismatchError:
        return False
    except Exception:
        return False


def validate_password_policy(password: str, settings: Settings) -> None:
    details: dict[str, str | int] = {}
    if len(password) < settings.password_min_length:
        details["min_length"] = settings.password_min_length
    if settings.password_require_uppercase and not re.search(r"[A-Z]", password):
        details["uppercase"] = "required"
    if settings.password_require_lowercase and not re.search(r"[a-z]", password):
        details["lowercase"] = "required"
    if settings.password_require_number and not re.search(r"\d", password):
        details["number"] = "required"
    if settings.password_require_special and not re.search(r"[^A-Za-z0-9]", password):
        details["special"] = "required"
    if details:
        raise bad_request("Password does not satisfy policy", "PASSWORD_POLICY_FAILED", details)
