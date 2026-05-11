from __future__ import annotations

import json
from copy import deepcopy
from typing import Any

from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi
from starlette.responses import HTMLResponse

PUBLIC_V1_PATHS = {
    "/v1/signup",
    "/v1/signin",
    "/v1/login",
    "/v1/token/refresh",
    "/v1/password/forgot",
    "/v1/password/reset",
    "/v1/admin/register",
}

SUCCESS_ENVELOPE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "required": ["status", "message", "data", "request_id", "trace_id", "timestamp"],
    "properties": {
        "status": {"type": "string", "enum": ["ok"]},
        "message": {"type": "string"},
        "data": {"type": "object"},
        "request_id": {"type": "string"},
        "trace_id": {"type": "string"},
        "timestamp": {"type": "string", "format": "date-time"},
    },
}

ERROR_ENVELOPE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "required": ["status", "message", "error_code", "details", "path", "request_id", "trace_id", "timestamp"],
    "properties": {
        "status": {"type": "string", "enum": ["error"]},
        "message": {"type": "string"},
        "error_code": {"type": "string"},
        "details": {"type": "object"},
        "path": {"type": "string"},
        "request_id": {"type": "string"},
        "trace_id": {"type": "string"},
        "timestamp": {"type": "string", "format": "date-time"},
    },
}


def custom_openapi(app: FastAPI) -> dict:
    if app.openapi_schema:
        return app.openapi_schema

    settings = app.state.settings
    schema = get_openapi(
        title="auth_service API",
        version=settings.version,
        description="Canonical authentication service API.",
        routes=app.routes,
        tags=app.openapi_tags,
        openapi_version="3.0.3",
    )

    schema["servers"] = [{"url": "/", "description": "Same origin as Swagger UI"}]
    components = schema.setdefault("components", {})
    components.setdefault("securitySchemes", {})["bearerAuth"] = {
        "type": "http",
        "scheme": "bearer",
        "bearerFormat": "JWT",
        "description": "Paste the auth_service JWT access token. Swagger UI will send it as a Bearer token.",
    }
    components.setdefault("schemas", {})["SuccessEnvelope"] = deepcopy(SUCCESS_ENVELOPE_SCHEMA)
    components.setdefault("schemas", {})["ErrorEnvelope"] = deepcopy(ERROR_ENVELOPE_SCHEMA)

    for path, methods in schema.get("paths", {}).items():
        for _, operation in methods.items():
            if not isinstance(operation, dict):
                continue

            responses = operation.setdefault("responses", {})
            if path.startswith("/v1/"):
                responses.setdefault("422", {"description": "Payload validation failed"})
                responses.setdefault("401", {"description": "Missing, invalid, expired, or revoked JWT"})
                responses.setdefault("403", {"description": "Valid JWT without sufficient permissions"})

            _normalize_response_objects(responses)

            if path.startswith("/v1/") and path not in PUBLIC_V1_PATHS:
                operation.setdefault("security", [{"bearerAuth": []}])

    _make_openapi_30_safe(schema)
    app.openapi_schema = schema
    return schema


def _normalize_response_objects(responses: dict[str, Any]) -> None:
    """Make response sections boring and Swagger-UI-safe.

    The browser error `Could not render responses_Responses` happens inside
    Swagger UI's response renderer before a request is sent. In practice it is
    triggered by brittle combinations of generated OpenAPI 3.x schemas and
    inline response examples. To keep Try-it-out, Curl, Request URL, and Server
    response working, all operation responses are normalized to explicit JSON
    envelope schemas and response examples are removed from the OpenAPI response
    object. Swagger will still show generated example values from the schema and
    will show real response bodies after Execute.
    """
    for status_code, response in list(responses.items()):
        if not isinstance(response, dict):
            responses[status_code] = {"description": "Response"}
            response = responses[status_code]

        response.setdefault("description", "Response")
        response.pop("links", None)

        content = response.setdefault("content", {})
        if not isinstance(content, dict):
            content = {}
            response["content"] = content

        media = content.setdefault("application/json", {})
        if not isinstance(media, dict):
            media = {}
            content["application/json"] = media

        # Remove explicit examples from responses. Swagger UI 5.x has had
        # response-render crashes around example rendering; schema-generated
        # examples are enough for documentation and do not block live responses.
        media.pop("example", None)
        media.pop("examples", None)

        if str(status_code).startswith("2"):
            media["schema"] = {"$ref": "#/components/schemas/SuccessEnvelope"}
        else:
            media["schema"] = {"$ref": "#/components/schemas/ErrorEnvelope"}


def _make_openapi_30_safe(value: Any, *, in_schema: bool = False) -> None:
    """Convert Pydantic JSON Schema output into conservative OpenAPI 3.0.

    This sanitizer intentionally avoids touching `example` values. Earlier code
    recursively replaced every boolean in the full document, which corrupted
    examples such as `email_verified: false` into schema-like objects. This
    function edits only schema metadata.
    """
    if isinstance(value, dict):
        current_is_schema = in_schema or _looks_like_schema(value)

        if current_is_schema:
            examples = value.pop("examples", None)
            if "example" not in value and isinstance(examples, list) and examples:
                value["example"] = examples[0]
            elif examples == {}:
                value.pop("examples", None)

            if value.get("additionalProperties") is True:
                value.pop("additionalProperties", None)

            _convert_nullable_anyof(value)

        for key, child in list(value.items()):
            if key in {"example", "examples"}:
                # Do not mutate literal examples.
                continue
            _make_openapi_30_safe(child, in_schema=current_is_schema or key in {"schema", "schemas", "properties", "items", "allOf", "anyOf", "oneOf"})

    elif isinstance(value, list):
        for child in value:
            _make_openapi_30_safe(child, in_schema=in_schema)


def _looks_like_schema(value: dict[str, Any]) -> bool:
    return any(k in value for k in ("type", "$ref", "properties", "items", "allOf", "anyOf", "oneOf", "enum", "format", "required"))


def _convert_nullable_anyof(schema: dict[str, Any]) -> None:
    any_of = schema.get("anyOf")
    if not isinstance(any_of, list) or len(any_of) != 2:
        return

    null_index = None
    real_schema = None
    for index, option in enumerate(any_of):
        if isinstance(option, dict) and option.get("type") == "null":
            null_index = index
        else:
            real_schema = option

    if null_index is None or not isinstance(real_schema, dict):
        return

    schema.pop("anyOf", None)
    for key, value in real_schema.items():
        schema.setdefault(key, value)
    schema["nullable"] = True


def swagger_ui_html(app: FastAPI) -> HTMLResponse:
    spec_json = json.dumps(custom_openapi(app), ensure_ascii=False, default=str)
    html = f"""
<!doctype html>
<html>
<head>
  <title>auth_service API Docs</title>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.32.5/swagger-ui.css" />
  <style>
    body {{ margin: 0; background: #ffffff; }}
    #swagger-ui {{ max-width: 1460px; margin: 0 auto; }}
  </style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script id="openapi-spec" type="application/json">{spec_json}</script>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.32.5/swagger-ui-bundle.js"></script>
  <script>
    function makeId(prefix) {{
      if (window.crypto && typeof window.crypto.randomUUID === "function") {{
        return prefix + crypto.randomUUID();
      }}
      return prefix + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 12);
    }}

    window.onload = function() {{
      const spec = JSON.parse(document.getElementById("openapi-spec").textContent);
      SwaggerUIBundle({{
        spec: spec,
        dom_id: '#swagger-ui',
        deepLinking: true,
        persistAuthorization: true,
        displayRequestDuration: true,
        tryItOutEnabled: true,
        filter: true,
        docExpansion: "list",
        defaultModelsExpandDepth: 2,
        defaultModelExpandDepth: 2,
        showExtensions: true,
        showCommonExtensions: true,
        defaultModelRendering: "example",
        syntaxHighlight: {{ activated: true }},
        requestInterceptor: function(req) {{
          req.headers["X-Request-ID"] = req.headers["X-Request-ID"] || makeId("req-");
          req.headers["X-Trace-ID"] = req.headers["X-Trace-ID"] || makeId("");
          req.headers["X-Correlation-ID"] = req.headers["X-Correlation-ID"] || req.headers["X-Request-ID"];
          return req;
        }}
      }});
    }};
  </script>
</body>
</html>
"""
    return HTMLResponse(html)
