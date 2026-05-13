from datetime import UTC, datetime

from app.config import load_settings
from app.domain.events import build_event_envelope
from app.domain.s3_keys import audit_snapshot_key
from app.http.responses import PrettyJSONResponse, error_envelope, success_envelope


def test_success_envelope_shape():
    body = success_envelope("resource loaded", {"x": 1})
    assert set(body) == {"status", "message", "data", "request_id", "trace_id", "timestamp"}
    assert body["status"] == "ok"


def test_error_envelope_shape():
    body = error_envelope("Authentication required", "UNAUTHORIZED", path="/v1/example")
    assert set(body) == {"status", "message", "error_code", "details", "path", "request_id", "trace_id", "timestamp"}
    assert body["error_code"] == "UNAUTHORIZED"


def test_pretty_json_response_has_indentation_and_newline():
    rendered = PrettyJSONResponse({"status": "ok", "service": {"name": "auth_service"}}).body.decode("utf-8")
    assert rendered.endswith("\n")
    assert '\n  "status": "ok"' in rendered


def test_canonical_event_envelope_and_redaction():
    settings = load_settings()
    event = build_event_envelope(
        settings,
        event_type="auth.signin.succeeded",
        user_id="user-1",
        actor_id="user-1",
        aggregate_type="session",
        aggregate_id="session-1",
        payload={"username": "jakir", "password": "secret", "refresh_token": "token"},
        request_id="req-1",
        trace_id="trace-1",
        correlation_id="corr-1",
        event_id="evt-1",
    )
    assert event["service"] == "auth_service"
    assert event["environment"] == "development"
    assert event["tenant"] == "dev"
    assert event["aggregate_type"] == "session"
    assert event["aggregate_id"] == "session-1"
    assert event["payload"]["password"] == "***REDACTED***"
    assert event["payload"]["refresh_token"] == "***REDACTED***"


def test_s3_audit_key_format():
    settings = load_settings()
    key = audit_snapshot_key(
        settings,
        actor_user_id="user-1",
        event_type="auth.signin.succeeded",
        event_id="evt-1",
        timestamp=datetime(2026, 5, 9, 10, 15, 30, tzinfo=UTC),
    )
    assert key == "auth_service/development/tenant/dev/users/user-1/events/2026/05/09/101530_auth_signin_succeeded_evt-1.json"


def test_password_reset_schema_accepts_reset_token_aliases():
    from app.domain.schemas import ResetPasswordRequest
    one = ResetPasswordRequest(reset_token="prt_x." + "x" * 30, new_password="Secret123!")
    two = ResetPasswordRequest(token="prt_x." + "y" * 30, new_password="Secret123!")
    assert one.effective_token.startswith("prt_x.")
    assert two.effective_token.startswith("prt_x.")


def test_signup_schema_supports_admin_request_option():
    from app.domain.schemas import SignupRequest
    payload = SignupRequest(
        username="admin-jakir",
        email="admin.jakir@example.com",
        password="Secret123!",
        account_type="admin",
        reason="I need admin access to manage operational issues.",
    )
    assert payload.account_type == "admin"
    assert payload.reason
