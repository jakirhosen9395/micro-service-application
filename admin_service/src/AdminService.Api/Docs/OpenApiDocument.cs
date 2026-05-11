using AdminService.Api.Configuration;
using AdminService.Api.Http;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace AdminService.Api.Docs;

public static class OpenApiDocument
{
    public static IResult SwaggerUi(AdminSettings settings)
    {
        var spec = BuildSpec(settings);
        var specJson = JsonSerializer.Serialize(spec, JsonOptionsFactory.Options);
        var encoded = JavaScriptEncoder.Default.Encode(specJson);
        var html = $$"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{{settings.ServiceName}} API Docs</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
  <style>
    body{margin:0;background:#f7f8fb;color:#172033;font-family:Inter,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}.topbar{display:none}.guide{max-width:1480px;margin:24px auto 0;padding:18px 22px;background:#fff;border:1px solid #d7dce6;border-radius:14px;box-shadow:0 8px 24px rgba(15,23,42,.06)}.guide h1{margin:0 0 8px;font-size:24px}.guide p{margin:6px 0;line-height:1.45}.guide-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:12px;margin-top:12px}.guide-card{border:1px solid #e3e7ef;border-radius:12px;padding:12px;background:#fbfcff}.token-row{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}.token-row input{flex:1;min-width:360px;border:1px solid #b9c2d0;border-radius:8px;padding:10px;font-family:monospace}.token-row button{border:0;border-radius:8px;padding:10px 14px;background:#2563eb;color:#fff;font-weight:700;cursor:pointer}.token-row button.secondary{background:#64748b}.token-status{font-size:13px;color:#475569;margin-top:8px}.swagger-ui .scheme-container{box-shadow:none;border-bottom:1px solid #e3e7ef}.swagger-ui{max-width:1480px;margin:0 auto}
  </style>
</head>
<body>
  <section class="guide">
    <h1>admin_service API console</h1>
    <p>All <strong>/v1/admin</strong> APIs require an Auth service JWT. The token must be valid, signed with the shared secret, have <code>role=admin</code>, <code>admin_status=approved</code>, and a tenant matching <code>{{settings.Tenant}}</code>.</p>
    <div class="token-row">
      <input id="admin-token" type="password" autocomplete="off" placeholder="Paste raw JWT or Bearer &lt;jwt&gt; from auth_service signin/login" />
      <button type="button" onclick="saveAdminToken()">Use token</button>
      <button type="button" class="secondary" onclick="clearAdminToken()">Clear token</button>
    </div>
    <div id="token-status" class="token-status">No token loaded. Calls without a token should return 401 Authentication required.</div>
    <div class="guide-grid">
      <div class="guide-card"><strong>How to get a token</strong><p>Login to auth_service first, then copy the access token. A normal user token is expected to return 403 because admin_service requires approved admin claims.</p></div>
      <div class="guide-card"><strong>Admin workflows</strong><p>Use registration approve/reject endpoints for admin requests, access-request approve/reject endpoints for cross-user access, and grant revoke to deactivate grants.</p></div>
      <div class="guide-card"><strong>Side effects</strong><p>Mutations write PostgreSQL rows, admin audit rows, outbox events, S3 audit snapshots, Redis cache invalidations/locks, MongoDB structured logs, and Kafka events.</p></div>
      <div class="guide-card"><strong>Events</strong><p>Important events include admin.registration.approved/rejected, access.request.approved/rejected, access.grant.created/revoked, admin.user.* requests, and admin.report.* requests.</p></div>
    </div>
  </section>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-standalone-preset.js"></script>
  <script>
    const spec = JSON.parse("{{encoded}}");
    const tokenKey = 'admin_service_bearer_token';
    const tokenInput = document.getElementById('admin-token');
    const tokenStatus = document.getElementById('token-status');
    const savedToken = localStorage.getItem(tokenKey) || '';
    if (savedToken) { tokenInput.value = savedToken; tokenStatus.textContent = 'Token loaded from this browser. Protected /v1/admin calls will include Authorization automatically.'; }
    function normalizeToken(value) { const t = (value || '').trim(); if (!t) return ''; return t.toLowerCase().startsWith('bearer ') ? t : 'Bearer ' + t; }
    function saveAdminToken() { const token = normalizeToken(tokenInput.value); if (!token) return clearAdminToken(); localStorage.setItem(tokenKey, token); tokenInput.value = token; tokenStatus.textContent = 'Token saved. Swagger requests to /v1/admin will include Authorization.'; }
    function clearAdminToken() { localStorage.removeItem(tokenKey); tokenInput.value = ''; tokenStatus.textContent = 'Token cleared. Protected calls should return 401.'; }
    function newId(prefix) { return prefix + '-' + Math.random().toString(16).slice(2) + Date.now().toString(16); }
    SwaggerUIBundle({
      spec,
      dom_id: '#swagger-ui',
      presets: [SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset],
      layout: 'BaseLayout',
      deepLinking: true,
      persistAuthorization: true,
      displayRequestDuration: true,
      tryItOutEnabled: true,
      filter: true,
      docExpansion: 'list',
      defaultModelsExpandDepth: 2,
      defaultModelExpandDepth: 2,
      showExtensions: true,
      showCommonExtensions: true,
      syntaxHighlight: { activated: true, theme: 'agate' },
      requestInterceptor: function(req) {
        req.headers = req.headers || {};
        req.headers['X-Request-ID'] = req.headers['X-Request-ID'] || newId('req');
        req.headers['X-Trace-ID'] = req.headers['X-Trace-ID'] || req.headers['X-Request-ID'];
        req.headers['X-Correlation-ID'] = req.headers['X-Correlation-ID'] || req.headers['X-Request-ID'];
        const requestPath = new URL(req.url, window.location.href).pathname;
        const token = localStorage.getItem(tokenKey);
        if (requestPath.startsWith('/v1/admin') && token && !req.headers.Authorization) req.headers.Authorization = token;
        return req;
      }
    });
  </script>
</body>
</html>
""";
        return Results.Content(html, "text/html; charset=utf-8");
    }

    private static object BuildSpec(AdminSettings settings)
    {
        var paths = new Dictionary<string, object?>();
        foreach (var path in ProtectedGetPaths()) paths[path] = PathItem(GetOperation(path));
        foreach (var path in ProtectedPostPaths()) paths[path] = PathItem(null, PostOperation(path));
        paths["/hello"] = PathItem(GetPublicOperation("Service identity check", HelloExample(settings)));
        paths["/health"] = PathItem(GetPublicOperation("Dependency health check", HealthExample(settings)));
        paths["/docs"] = PathItem(GetPublicOperation("Swagger UI", new { status = "ok" }));

        var decisionSchema = new { type = "object", properties = new { reason = new { type = "string", example = "Verified request" } } };
        var accessApprovalSchema = new { type = "object", properties = new { scope = new { type = "string", example = "calculator:history:read" }, expires_at = new { type = "string", format = "date-time", example = "2030-01-01T00:00:00Z" }, reason = new { type = "string", example = "Approved for support investigation" } } };
        var adminReportSchema = new { type = "object", required = new[] { "report_type", "format" }, properties = new { report_type = new { type = "string", example = "calculator_history_report" }, target_user_id = new { type = "string", nullable = true, example = "user-uuid" }, format = new { type = "string", example = "pdf" }, date_from = new { type = "string", format = "date", example = "2026-05-01" }, date_to = new { type = "string", format = "date", example = "2026-05-09" }, filters = new { type = "object", additionalProperties = true }, options = new { type = "object", additionalProperties = true } } };

        return new
        {
            openapi = "3.0.3",
            info = new { title = "admin_service API", version = settings.Version, description = "Admin control plane, approvals, access grants, projections, and audit." },
            servers = new[] { new { url = "/", description = "current browser origin" } },
            components = new
            {
                securitySchemes = new Dictionary<string, object>
                {
                    ["bearerAuth"] = new { type = "http", scheme = "bearer", bearerFormat = "JWT", description = "auth_service JWT with role=admin, admin_status=approved, and matching tenant" }
                },
                schemas = new Dictionary<string, object>
                {
                    ["DecisionRequest"] = decisionSchema,
                    ["AccessApprovalRequest"] = accessApprovalSchema,
                    ["AdminReportRequest"] = adminReportSchema,
                    ["decision_request"] = decisionSchema,
                    ["access_approval_request"] = accessApprovalSchema,
                    ["admin_report_request"] = adminReportSchema
                }
            },
            paths
        };
    }

    private static object PathItem(object? get = null, object? post = null)
    {
        var d = new Dictionary<string, object?>();
        if (get is not null) d["get"] = get;
        if (post is not null) d["post"] = post;
        return d;
    }

    private static object GetPublicOperation(string summary, object example) => new
    {
        summary,
        responses = new Dictionary<string, object> { ["200"] = Response("ok", example) }
    };

    private static object GetOperation(string path) => new
    {
        summary = Summary(path),
        description = Description(path, "read projection data from PostgreSQL and Redis cache when applicable; log request outcome to MongoDB"),
        security = BearerSecurity(),
        parameters = PathParameters(path),
        responses = ProtectedResponses()
    };

    private static object PostOperation(string path) => new
    {
        summary = Summary(path),
        description = Description(path, "write domain state and audit rows in PostgreSQL, invalidate Redis caches or use Redis locks, write S3 audit snapshots, enqueue Kafka outbox events, and write MongoDB structured logs"),
        security = BearerSecurity(),
        parameters = PathParameters(path),
        requestBody = RequestBodyFor(path),
        responses = ProtectedResponses("200")
    };

    private static object[] BearerSecurity() => new object[] { new Dictionary<string, string[]> { ["bearerAuth"] = Array.Empty<string>() } };

    private static Dictionary<string, object> ProtectedResponses(string successCode = "200") => new()
    {
        [successCode] = Response("ok", SuccessExample()),
        ["400"] = ErrorResponse("BAD_REQUEST", "Invalid request"),
        ["401"] = ErrorResponse("UNAUTHORIZED", "Authentication required"),
        ["403"] = ErrorResponse("FORBIDDEN", "Approved admin access required"),
        ["404"] = ErrorResponse("NOT_FOUND", "Resource not found"),
        ["409"] = ErrorResponse("CONFLICT", "Resource conflict"),
        ["422"] = ErrorResponse("VALIDATION_ERROR", "Validation failed")
    };

    private static object Response(string description, object example) => new
    {
        description,
        content = new Dictionary<string, object>
        {
            ["application/json"] = new { example }
        }
    };

    private static object ErrorResponse(string code, string message) => new
    {
        description = message,
        content = new Dictionary<string, object>
        {
            ["application/json"] = new
            {
                example = new { status = "error", message, error_code = code, details = new { }, path = "/v1/admin/example", request_id = "req-uuid", trace_id = "trace-id", timestamp = "2026-05-09T00:00:00.000Z" }
            }
        }
    };

    private static object RequestBodyFor(string path)
    {
        var schemaRef = path.Contains("access-requests", StringComparison.Ordinal) && path.EndsWith("/approve", StringComparison.Ordinal)
            ? "#/components/schemas/AccessApprovalRequest"
            : path == "/v1/admin/reports"
                ? "#/components/schemas/AdminReportRequest"
                : "#/components/schemas/DecisionRequest";
        return new
        {
            required = true,
            content = new Dictionary<string, object>
            {
                ["application/json"] = new
                {
                    schema = new Dictionary<string, string> { ["$ref"] = schemaRef },
                    examples = BodyExamples(schemaRef)
                }
            }
        };
    }

    private static Dictionary<string, object> BodyExamples(string schemaRef) => schemaRef switch
    {
        "#/components/schemas/AccessApprovalRequest" => new Dictionary<string, object> { ["default"] = new { value = new { scope = "calculator:history:read", expires_at = "2030-01-01T00:00:00Z", reason = "Approved for support investigation" } } },
        "#/components/schemas/AdminReportRequest" => new Dictionary<string, object> { ["default"] = new { value = new { report_type = "calculator_history_report", target_user_id = "user-uuid", format = "pdf", date_from = "2026-05-01", date_to = "2026-05-09", filters = new { }, options = new { } } } },
        _ => new Dictionary<string, object> { ["default"] = new { value = new { reason = "Verified request" } } }
    };

    private static object[] PathParameters(string path)
    {
        var names = new List<string>();
        var start = 0;
        while ((start = path.IndexOf('{', start)) >= 0)
        {
            var end = path.IndexOf('}', start + 1);
            if (end < 0) break;
            names.Add(path[(start + 1)..end]);
            start = end + 1;
        }

        return names.Select(name => (object)new
        {
            name,
            @in = "path",
            required = true,
            schema = new { type = "string" },
            example = ExampleForParameter(name)
        }).ToArray();
    }

    private static string ExampleForParameter(string name) => name switch
    {
        "requestId" => "request-uuid",
        "grantId" => "grant-uuid",
        "userId" => "user-uuid",
        "calculationId" => "calculation-uuid",
        "todoId" => "todo-uuid",
        "reportId" => "report-uuid",
        "eventId" => "event-uuid",
        _ => "id"
    };

    private static string Summary(string path) => path.Replace("/v1/admin/", string.Empty, StringComparison.Ordinal).Replace("{", string.Empty, StringComparison.Ordinal).Replace("}", string.Empty, StringComparison.Ordinal).Replace('/', ' ');

    private static string Description(string path, string sideEffects) => $"Approved admin JWT required. This operation validates issuer, audience, signature, lifetime, role=admin, admin_status=approved, and tenant. Side effects: {sideEffects}.";

    private static object SuccessExample() => new { status = "ok", message = "resource loaded", data = new { }, request_id = "req-uuid", trace_id = "trace-id", timestamp = "2026-05-09T00:00:00.000Z" };

    private static object HelloExample(AdminSettings settings) => new { status = "ok", message = "admin_service is running", service = new { name = settings.ServiceName, env = settings.EnvironmentName, version = settings.Version } };

    private static object HealthExample(AdminSettings settings) => new
    {
        status = "ok",
        service = settings.ServiceName,
        version = settings.Version,
        environment = settings.EnvironmentName,
        timestamp = "2026-05-09T00:00:00.000Z",
        dependencies = new Dictionary<string, object>
        {
            ["jwt"] = new { status = "ok", latency_ms = 0.0 },
            ["postgres"] = new { status = "ok", latency_ms = 0.0 },
            ["redis"] = new { status = "ok", latency_ms = 0.0 },
            ["kafka"] = new { status = "ok", latency_ms = 0.0 },
            ["s3"] = new { status = "ok", latency_ms = 0.0 },
            ["mongodb"] = new { status = "ok", latency_ms = 0.0 },
            ["apm"] = new { status = "ok", latency_ms = 0.0 },
            ["elasticsearch"] = new { status = "ok", latency_ms = 0.0 }
        }
    };

    private static IEnumerable<string> ProtectedGetPaths() => new[]
    {
        "/v1/admin/dashboard",
        "/v1/admin/summary",
        "/v1/admin/registrations",
        "/v1/admin/registrations/{requestId}",
        "/v1/admin/access-requests",
        "/v1/admin/access-requests/{requestId}",
        "/v1/admin/access-grants",
        "/v1/admin/access-grants/{grantId}",
        "/v1/admin/users",
        "/v1/admin/users/{userId}",
        "/v1/admin/users/{userId}/activity",
        "/v1/admin/users/{userId}/access-grants",
        "/v1/admin/users/{userId}/reports",
        "/v1/admin/calculations",
        "/v1/admin/calculations/{calculationId}",
        "/v1/admin/calculations/users/{userId}",
        "/v1/admin/calculations/summary",
        "/v1/admin/todos",
        "/v1/admin/todos/{todoId}",
        "/v1/admin/todos/users/{userId}",
        "/v1/admin/todos/summary",
        "/v1/admin/reports",
        "/v1/admin/reports/{reportId}",
        "/v1/admin/reports/users/{userId}",
        "/v1/admin/reports/summary",
        "/v1/admin/audit",
        "/v1/admin/audit/{eventId}"
    };

    private static IEnumerable<string> ProtectedPostPaths() => new[]
    {
        "/v1/admin/registrations/{requestId}/approve",
        "/v1/admin/registrations/{requestId}/reject",
        "/v1/admin/access-requests/{requestId}/approve",
        "/v1/admin/access-requests/{requestId}/reject",
        "/v1/admin/access-grants/{grantId}/revoke",
        "/v1/admin/users/{userId}/suspend",
        "/v1/admin/users/{userId}/activate",
        "/v1/admin/users/{userId}/force-password-reset",
        "/v1/admin/reports",
        "/v1/admin/reports/{reportId}/cancel"
    };
}
