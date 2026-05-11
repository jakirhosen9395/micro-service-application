from fastapi.testclient import TestClient

from app.main import create_app
from app.http.docs import custom_openapi


def test_public_routes_and_rejected_routes():
    app = create_app(lifespan_enabled=False)
    client = TestClient(app)
    hello = client.get("/hello")
    assert hello.status_code == 200
    assert hello.json()["message"] == "auth_service is running"
    docs = client.get("/docs")
    assert docs.status_code == 200
    for path in ["/", "/live", "/ready", "/healthy", "/openapi.json"]:
        assert client.get(path).status_code == 404


def test_protected_v1_route_rejects_missing_token():
    app = create_app(lifespan_enabled=False)
    client = TestClient(app)
    response = client.get("/v1/me")
    assert response.status_code == 401
    body = response.json()
    assert body["status"] == "error"
    assert body["error_code"] == "UNAUTHORIZED"


def test_docs_openapi_uses_same_origin_server():
    app = create_app(lifespan_enabled=False)
    schema = custom_openapi(app)
    assert schema["servers"] == [{"url": "/", "description": "Same origin as Swagger UI"}]



def test_admin_route_without_token_is_rejected():
    app = create_app(lifespan_enabled=False)
    client = TestClient(app)
    response = client.get("/v1/admin/requests")
    assert response.status_code in {401, 403}


def test_docs_html_is_plain_swagger_without_custom_guide_panel():
    app = create_app(lifespan_enabled=False)
    client = TestClient(app)
    html = client.get("/docs").text
    assert "Auth Service API Console" not in html
    assert "How to use" not in html
    assert "Side effects and observability" not in html
    assert "persistAuthorization: true" in html
    assert "requestInterceptor" in html


def test_openapi_security_and_protected_responses():
    app = create_app(lifespan_enabled=False)
    schema = custom_openapi(app)
    assert "bearerAuth" in schema["components"]["securitySchemes"]
    protected = schema["paths"]["/v1/me"]["get"]
    assert protected["security"] == [{"bearerAuth": []}]
    assert "401" in protected["responses"]
    assert "403" in protected["responses"]


def test_openapi_responses_have_renderable_object_schemas():
    app = create_app(lifespan_enabled=False)
    schema = custom_openapi(app)
    for path, methods in schema["paths"].items():
        for operation in methods.values():
            if not isinstance(operation, dict):
                continue
            for response in operation.get("responses", {}).values():
                for media in response.get("content", {}).values():
                    assert media.get("schema") != {}
                    assert media.get("schema") is not None


def test_openapi_is_303_and_every_response_has_json_content_for_swagger_ui():
    app = create_app(lifespan_enabled=False)
    schema = custom_openapi(app)
    assert schema["openapi"] == "3.0.3"
    for path, methods in schema["paths"].items():
        for operation in methods.values():
            if not isinstance(operation, dict):
                continue
            for response in operation.get("responses", {}).values():
                content = response.get("content")
                assert isinstance(content, dict), f"missing content for {path}: {response}"
                assert "application/json" in content, f"missing json response for {path}: {response}"
                media = content["application/json"]
                assert isinstance(media.get("schema"), dict)
                assert media["schema"] != {}
                # Response examples are intentionally omitted because Swagger UI 5.x
                # can crash its responses renderer on some inline example shapes.
                assert "example" not in media
                assert "examples" not in media


def test_docs_html_forces_example_response_rendering():
    app = create_app(lifespan_enabled=False)
    client = TestClient(app)
    html = client.get("/docs").text
    assert 'defaultModelRendering: "example"' in html
    assert '"openapi": "3.0.3"' in html


def test_openapi_does_not_corrupt_boolean_examples_or_emit_response_examples():
    app = create_app(lifespan_enabled=False)
    schema = custom_openapi(app)
    dumped = str(schema)
    assert "{'not': {}}" not in dumped
    for path, methods in schema["paths"].items():
        for operation in methods.values():
            if not isinstance(operation, dict):
                continue
            for response in operation.get("responses", {}).values():
                media = response.get("content", {}).get("application/json", {})
                assert "example" not in media, path
                assert "examples" not in media, path

def test_docs_html_uses_latest_swagger_and_safe_request_id_fallback():
    app = create_app(lifespan_enabled=False)
    client = TestClient(app)
    html = client.get("/docs").text
    assert "swagger-ui-dist@5.32.5" in html
    assert "function makeId(prefix)" in html
    assert "crypto.randomUUID" in html
