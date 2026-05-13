from __future__ import annotations

import re
from datetime import date, datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

Gender = Literal["male", "female", "other", "prefer_not_to_say"]
Decision = Literal["approve", "reject"]
AccountType = Literal["user", "admin"]


class SignupRequest(BaseModel):
    username: str = Field(..., min_length=3, max_length=64, examples=["jakir"])
    email: EmailStr = Field(..., examples=["jakir@example.com"])
    password: str = Field(..., min_length=1, examples=["Secret123!"])
    full_name: str | None = Field(None, max_length=255, examples=["Md Jakir Hosen"])
    birthdate: date | None = Field(None, examples=["1998-05-20"])
    gender: Gender | None = Field(None, examples=["male"])
    account_type: AccountType = Field("user", description="Use admin to create an admin registration request through /v1/signup.", examples=["user"])
    reason: str | None = Field(None, min_length=10, max_length=2000, description="Required when account_type is admin.", examples=["I need admin access to manage users and review operational issues."])

    @field_validator("username")
    @classmethod
    def normalize_username(cls, value: str) -> str:
        value = value.strip().lower()
        if not re.fullmatch(r"[a-z0-9_.-]{3,64}", value):
            raise ValueError("username may contain lowercase letters, digits, dots, underscores, and hyphens")
        return value

    @field_validator("birthdate")
    @classmethod
    def birthdate_not_future(cls, value: date | None) -> date | None:
        if value and value > date.today():
            raise ValueError("birthdate cannot be in the future")
        return value


class AdminRegisterRequest(SignupRequest):
    reason: str = Field(..., min_length=10, max_length=2000, examples=["I need admin access to manage users and review operational issues."])


class SigninRequest(BaseModel):
    username_or_email: str = Field(..., min_length=1, examples=["jakir"])
    password: str = Field(..., min_length=1, examples=["secret"])
    device_id: str | None = Field(None, max_length=128, examples=["browser-1"])


class RefreshTokenRequest(BaseModel):
    refresh_token: str = Field(..., min_length=20, examples=["refresh-token-from-signin"])


class ForgotPasswordRequest(BaseModel):
    email: EmailStr | None = Field(None, examples=["jakir@example.com"])
    identifier: str | None = Field(None, min_length=1, examples=["jakir@example.com"])
    username: str | None = Field(None, min_length=1, examples=["jakir"])
    username_or_email: str | None = Field(None, min_length=1, examples=["jakir@example.com"])

    @property
    def lookup_value(self) -> str:
        value = self.email or self.identifier or self.username_or_email or self.username
        if not value:
            raise ValueError("email, identifier, username, or username_or_email is required")
        return str(value).strip().lower()


class ResetPasswordRequest(BaseModel):
    reset_token: str | None = Field(None, min_length=20, examples=["reset-token"])
    token: str | None = Field(None, min_length=20, examples=["reset-token"], description="Alias for reset_token.")
    new_password: str = Field(..., min_length=1, examples=["new-secret"])

    @property
    def effective_token(self) -> str:
        value = self.reset_token or self.token
        if not value:
            raise ValueError("reset_token is required")
        return value


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(..., min_length=1, examples=["secret"])
    new_password: str = Field(..., min_length=1, examples=["new-secret"])


class AdminDecisionRequest(BaseModel):
    decision: Decision = Field(..., examples=["approve"])
    reason: str = Field(..., min_length=3, max_length=2000, examples=["Verified request"])


class SafeUser(BaseModel):
    id: str
    username: str
    email: EmailStr
    full_name: str | None = None
    birthdate: date | None = None
    gender: Gender | None = None
    role: str
    admin_status: str
    tenant: str
    status: str
    email_verified: bool
    created_at: datetime | str | None = None
    updated_at: datetime | str | None = None
    last_login_at: datetime | str | None = None
    admin_requested_at: datetime | str | None = None
    admin_reviewed_at: datetime | str | None = None
    admin_reviewed_by: str | None = None
    admin_request_reason: str | None = None
    admin_decision_reason: str | None = None

    model_config = ConfigDict(from_attributes=True)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    expires_in: int


class AuthData(BaseModel):
    user: SafeUser
    tokens: TokenPair


class VerifyData(BaseModel):
    active: bool
    claims: dict[str, Any]
    user: SafeUser | None = None
