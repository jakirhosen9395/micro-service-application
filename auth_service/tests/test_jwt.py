from app.config import load_settings
from app.security.tokens import build_access_claims, decode_access_token, encode_access_token


def test_access_token_contains_required_claims_only_for_auth_contract():
    settings = load_settings()
    user = {
        "id": "user-1",
        "username": "jakir",
        "email": "jakir@example.com",
        "role": "user",
        "admin_status": "not_requested",
        "tenant": settings.tenant,
        "status": "active",
    }
    claims = build_access_claims(settings, user, "jti-1")
    token = encode_access_token(settings, claims)
    decoded = decode_access_token(settings, token)
    for key in ["iss", "aud", "sub", "jti", "username", "email", "role", "admin_status", "tenant", "iat", "nbf", "exp"]:
        assert key in decoded
    assert decoded["iss"] == "auth"
    assert decoded["aud"] == "micro-app"
    assert decoded["sub"] == "user-1"
    assert "password" not in decoded
    assert "refresh_token" not in decoded
