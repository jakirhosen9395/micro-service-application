package docs

import (
	"encoding/json"
	"fmt"
	"html/template"

	"user_service/internal/config"
)

func HTML(cfg config.Config) string {
	spec := openAPI(cfg)
	b, _ := json.Marshal(spec)
	return fmt.Sprintf(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>%s API Docs</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
  <style>
    body{margin:0;background:#f8fafc;color:#0f172a;font-family:Inter,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}.topbar{display:none}#swagger-ui{max-width:1240px;margin:auto}.swagger-ui .scheme-container{border-radius:12px}
  </style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script>
    function id(prefix){ return prefix + '-' + Math.random().toString(36).slice(2) + Date.now().toString(36); }
    window.onload = function() {
      SwaggerUIBundle({
        spec: %s,
        dom_id: '#swagger-ui',
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
        syntaxHighlight: { activated: true },
        requestInterceptor: function(req) {
          req.headers = req.headers || {};
          if (!req.headers['X-Request-ID']) req.headers['X-Request-ID'] = id('req');
          if (!req.headers['X-Trace-ID']) req.headers['X-Trace-ID'] = id('trace');
          if (!req.headers['X-Correlation-ID']) req.headers['X-Correlation-ID'] = id('corr');
          return req;
        }
      });
    };
  </script>
</body>
</html>`, template.HTMLEscapeString(cfg.ServiceName), string(b))
}

func openAPI(cfg config.Config) map[string]any {
	paths := map[string]any{
		"/hello":  publicJSON("Service identity check", helloExample(cfg)),
		"/health": publicJSON("Dependency health check", healthExample(cfg), "503"),
		"/docs":   publicHTML("Swagger UI"),

		"/v1/users/me":                                          map[string]any{"get": readOp("profile", "Current profile", nil), "patch": updateOp("profile", "Update current profile", profilePatchExample())},
		"/v1/users/me/preferences":                              map[string]any{"get": readOp("preferences", "Current preferences", nil), "put": updateOp("preferences", "Replace preferences", preferencesExample())},
		"/v1/users/me/activity":                                 map[string]any{"get": readOp("activity", "Current user activity", pageParameters())},
		"/v1/users/me/dashboard":                                map[string]any{"get": readOp("dashboard", "Current user dashboard", nil)},
		"/v1/users/me/security-context":                         map[string]any{"get": readOp("security", "Current JWT and authorization context", nil)},
		"/v1/users/me/rbac":                                     map[string]any{"get": readOp("security", "Current RBAC/ABAC view", nil)},
		"/v1/users/me/effective-permissions":                    map[string]any{"get": readOp("security", "Current effective permissions", nil)},
		"/v1/users/me/calculations":                             map[string]any{"get": readOp("calculations", "Own projected calculation history", pageParameters())},
		"/v1/users/me/calculations/{calculationId}":             map[string]any{"get": pathReadOp("calculations", "Own projected calculation detail", []string{"calculationId"})},
		"/v1/users/{targetUserId}/calculations":                 map[string]any{"get": pathReadOpWithQuery("calculations", "Cross-user calculation projections with grant/admin/service", []string{"targetUserId"}, pageParameters())},
		"/v1/users/{targetUserId}/calculations/{calculationId}": map[string]any{"get": pathReadOp("calculations", "Cross-user calculation detail with grant/admin/service", []string{"targetUserId", "calculationId"})},

		"/v1/users/me/todos":                      map[string]any{"get": readOp("todos", "Own todo projections", pageParameters())},
		"/v1/users/me/todos/summary":              map[string]any{"get": readOp("todos", "Own todo summary", nil)},
		"/v1/users/me/todos/activity":             map[string]any{"get": readOp("todos", "Own todo activity", pageParameters())},
		"/v1/users/me/todos/{todoId}":             map[string]any{"get": pathReadOp("todos", "Own todo projection detail", []string{"todoId"})},
		"/v1/users/{targetUserId}/todos":          map[string]any{"get": pathReadOpWithQuery("todos", "Cross-user todo projections with grant/admin/service", []string{"targetUserId"}, pageParameters())},
		"/v1/users/{targetUserId}/todos/summary":  map[string]any{"get": pathReadOp("todos", "Cross-user todo summary with grant/admin/service", []string{"targetUserId"})},
		"/v1/users/{targetUserId}/todos/activity": map[string]any{"get": pathReadOpWithQuery("todos", "Cross-user todo activity with grant/admin/service", []string{"targetUserId"}, pageParameters())},
		"/v1/users/{targetUserId}/todos/{todoId}": map[string]any{"get": pathReadOp("todos", "Cross-user todo detail with grant/admin/service", []string{"targetUserId", "todoId"})},

		"/v1/users/access-requests":                    map[string]any{"post": createOp("access", "Request cross-user access", accessRequestExample()), "get": readOp("access", "List caller access requests", pageParameters())},
		"/v1/users/access-requests/{requestId}":        map[string]any{"get": pathReadOp("access", "Get one caller access request", []string{"requestId"})},
		"/v1/users/access-requests/{requestId}/cancel": map[string]any{"post": actionOp("access", "Cancel caller access request", []string{"requestId"}, nil, true)},
		"/v1/users/access-grants":                      map[string]any{"get": readOp("access", "List grants visible to caller", pageParameters())},

		"/v1/users/reports/types":                              map[string]any{"get": readOp("reports", "List local report types", nil)},
		"/v1/users/me/reports":                                 map[string]any{"post": createOp("reports", "Create own report request", reportExample()), "get": readOp("reports", "List own report requests", pageParameters())},
		"/v1/users/me/reports/{reportId}":                      map[string]any{"get": pathReadOp("reports", "Get own report request", []string{"reportId"})},
		"/v1/users/me/reports/{reportId}/metadata":             map[string]any{"get": pathReadOp("reports", "Own report metadata", []string{"reportId"})},
		"/v1/users/me/reports/{reportId}/progress":             map[string]any{"get": pathReadOp("reports", "Own report progress", []string{"reportId"})},
		"/v1/users/me/reports/{reportId}/cancel":               map[string]any{"post": actionOp("reports", "Cancel own report request", []string{"reportId"}, nil, true)},
		"/v1/users/{targetUserId}/reports":                     map[string]any{"post": createPathOp("reports", "Request report for another user with grant/admin/service", []string{"targetUserId"}, reportExample()), "get": pathReadOpWithQuery("reports", "List cross-user report requests with grant/admin/service", []string{"targetUserId"}, pageParameters())},
		"/v1/users/{targetUserId}/reports/{reportId}":          map[string]any{"get": pathReadOp("reports", "Get cross-user report request with grant/admin/service", []string{"targetUserId", "reportId"})},
		"/v1/users/{targetUserId}/reports/{reportId}/metadata": map[string]any{"get": pathReadOp("reports", "Cross-user report metadata", []string{"targetUserId", "reportId"})},
		"/v1/users/{targetUserId}/reports/{reportId}/progress": map[string]any{"get": pathReadOp("reports", "Cross-user report progress", []string{"targetUserId", "reportId"})},
		"/v1/users/{targetUserId}/reports/{reportId}/cancel":   map[string]any{"post": actionOp("reports", "Cancel cross-user report request with grant/admin/service", []string{"targetUserId", "reportId"}, nil, true)},
	}
	return map[string]any{
		"openapi": "3.0.3",
		"info": map[string]any{
			"title":       "user_service API",
			"version":     cfg.Version,
			"description": "Canonical Go/net/http user_service for profiles, preferences, dashboard, local projections, access requests, grants, and user report requests. All /v1 APIs require auth_service JWT bearer tokens.",
		},
		"servers": []map[string]any{{"url": "/"}},
		"paths":   paths,
		"components": map[string]any{
			"securitySchemes": map[string]any{"bearerAuth": map[string]any{"type": "http", "scheme": "bearer", "bearerFormat": "JWT"}},
			"schemas":         schemas(),
		},
	}
}

func helloExample(cfg config.Config) map[string]any {
	return map[string]any{"status": "ok", "message": "user_service is running", "service": map[string]any{"name": "user_service", "env": cfg.Environment, "version": cfg.Version}}
}

func healthExample(cfg config.Config) map[string]any {
	return map[string]any{"status": "ok", "service": "user_service", "version": cfg.Version, "environment": cfg.Environment, "timestamp": "2026-05-09T00:00:00Z", "dependencies": map[string]any{"jwt": dep(), "postgres": dep(), "redis": dep(), "kafka": dep(), "s3": dep(), "mongodb": dep(), "apm": dep(), "elasticsearch": dep()}}
}

func dep() map[string]any { return map[string]any{"status": "ok", "latency_ms": 0.0} }

func profilePatchExample() map[string]any {
	return map[string]any{"full_name": "Md Jakir Hosen", "display_name": "Jakir", "bio": "Microservice user", "birthdate": "1998-05-20", "gender": "male", "timezone": "Asia/Dhaka", "locale": "en", "avatar_url": "https://example.com/avatar.png", "phone": "+8801000000000", "metadata": map[string]any{"source": "swagger"}}
}

func preferencesExample() map[string]any {
	return map[string]any{"timezone": "Asia/Dhaka", "locale": "en", "theme": "dark", "notifications_enabled": true, "notification_settings": map[string]any{"email": true, "push": false}, "dashboard_settings": map[string]any{"density": "comfortable", "default_view": "summary"}, "report_settings": map[string]any{"default_format": "pdf"}, "privacy_settings": map[string]any{"profile_visibility": "private"}, "access_request_settings": map[string]any{"auto_expire_days": 30}, "metadata": map[string]any{"source": "swagger"}}
}

func accessRequestExample() map[string]any {
	return map[string]any{"target_user_id": "other-user-uuid", "resource_type": "calculator", "scope": "calculator:history:read", "reason": "Need to review calculation history for support investigation.", "expires_at": "2026-06-07T00:00:00Z"}
}

func reportExample() map[string]any {
	return map[string]any{"report_type": "calculator_history_report", "format": "pdf", "date_from": "2026-05-01", "date_to": "2026-05-09", "filters": map[string]any{}, "options": map[string]any{}}
}

func publicJSON(summary string, example map[string]any, extraCodes ...string) map[string]any {
	responses := map[string]any{"200": response("Success", example)}
	for _, code := range extraCodes {
		if code == "503" {
			responses[code] = response("Dependency health check failed", healthDownExample())
		}
	}
	responses["405"] = response("Method not allowed", errorExample("METHOD_NOT_ALLOWED", "Method not allowed"))
	return map[string]any{"get": map[string]any{"tags": []string{"system"}, "summary": summary, "security": []any{}, "responses": responses}}
}

func publicHTML(summary string) map[string]any {
	return map[string]any{"get": map[string]any{"tags": []string{"system"}, "summary": summary, "security": []any{}, "responses": map[string]any{"200": map[string]any{"description": "Swagger UI HTML", "content": map[string]any{"text/html": map[string]any{"schema": map[string]any{"type": "string"}}}}, "405": response("Method not allowed", errorExample("METHOD_NOT_ALLOWED", "Method not allowed"))}}}
}

func readOp(tag, summary string, queryParams []map[string]any) map[string]any {
	m := protectedOp(tag, summary, successResponses(false))
	if len(queryParams) > 0 {
		m["parameters"] = queryParams
	}
	return m
}

func pathReadOp(tag, summary string, pathNames []string) map[string]any {
	return pathReadOpWithQuery(tag, summary, pathNames, nil)
}

func pathReadOpWithQuery(tag, summary string, pathNames []string, queryParams []map[string]any) map[string]any {
	m := readOp(tag, summary, nil)
	m["parameters"] = append(pathParameters(pathNames), queryParams...)
	return m
}

func updateOp(tag, summary string, body any) map[string]any {
	m := protectedOp(tag, summary, successResponses(false))
	m["requestBody"] = requestBody(body)
	return m
}

func createOp(tag, summary string, body any) map[string]any {
	m := protectedOp(tag, summary, successResponses(true))
	m["requestBody"] = requestBody(body)
	return m
}

func createPathOp(tag, summary string, pathNames []string, body any) map[string]any {
	m := createOp(tag, summary, body)
	m["parameters"] = pathParameters(pathNames)
	return m
}

func actionOp(tag, summary string, pathNames []string, body any, canConflict bool) map[string]any {
	responses := successResponses(false)
	if canConflict {
		responses["409"] = response("Conflict", errorExample("CONFLICT", "Resource state conflict"))
	}
	m := protectedOp(tag, summary, responses)
	m["parameters"] = pathParameters(pathNames)
	if body != nil {
		m["requestBody"] = requestBody(body)
	}
	return m
}

func protectedOp(tag, summary string, responses map[string]any) map[string]any {
	return map[string]any{"tags": []string{tag}, "summary": summary, "security": []map[string][]string{{"bearerAuth": []string{}}}, "responses": responses}
}

func successResponses(created bool) map[string]any {
	responses := errorResponses()
	if created {
		responses["201"] = response("Created", successExample("resource created"))
	} else {
		responses["200"] = response("Success", successExample("resource loaded"))
	}
	return responses
}

func errorResponses() map[string]any {
	return map[string]any{
		"400": response("Validation error", errorExample("VALIDATION_ERROR", "Invalid request")),
		"401": response("Authentication required", errorExample("UNAUTHORIZED", "Authentication required")),
		"403": response("Forbidden", errorExample("FORBIDDEN", "Insufficient permissions")),
		"404": response("Not found", errorExample("NOT_FOUND", "Resource not found")),
		"405": response("Method not allowed", errorExample("METHOD_NOT_ALLOWED", "Method not allowed")),
		"500": response("Internal server error", errorExample("INTERNAL_ERROR", "Internal server error")),
	}
}

func requestBody(example any) map[string]any {
	return map[string]any{"required": true, "content": map[string]any{"application/json": map[string]any{"schema": map[string]any{"type": "object", "additionalProperties": true}, "example": example, "examples": bodyExamples(example)}}}
}

func bodyExamples(valid any) map[string]any {
	return map[string]any{
		"valid":              map[string]any{"summary": "Valid request body", "value": valid},
		"malformed_json":     map[string]any{"summary": "Invalid JSON example", "value": "{"},
		"missing_required":   map[string]any{"summary": "Missing required fields example", "value": map[string]any{}},
		"unknown_field":      map[string]any{"summary": "Unknown field example", "value": map[string]any{"unknown_field": true}},
		"unsupported_format": map[string]any{"summary": "Report format validation example", "value": map[string]any{"report_type": "calculator_history_report", "format": "docx"}},
	}
}

func pathParameters(names []string) []map[string]any {
	params := make([]map[string]any, 0, len(names))
	for _, n := range names {
		params = append(params, map[string]any{"name": n, "in": "path", "required": true, "schema": map[string]any{"type": "string", "minLength": 1}, "examples": map[string]any{"valid": map[string]any{"value": n + "-example"}, "not_found": map[string]any{"value": "missing-" + n}}})
	}
	return params
}

func pageParameters() []map[string]any {
	return []map[string]any{
		{"name": "limit", "in": "query", "required": false, "schema": map[string]any{"type": "integer", "minimum": 1, "maximum": 100, "default": 50}, "examples": map[string]any{"valid": map[string]any{"value": 20}, "invalid_text": map[string]any{"value": "abc"}, "invalid_zero": map[string]any{"value": 0}, "invalid_too_large": map[string]any{"value": 101}}},
		{"name": "offset", "in": "query", "required": false, "schema": map[string]any{"type": "integer", "minimum": 0, "default": 0}, "examples": map[string]any{"valid": map[string]any{"value": 0}, "invalid_text": map[string]any{"value": "abc"}, "invalid_negative": map[string]any{"value": -1}}},
	}
}

func response(description string, example any) map[string]any {
	return map[string]any{"description": description, "content": map[string]any{"application/json": map[string]any{"schema": map[string]any{"type": "object"}, "example": example}}}
}

func successExample(message string) map[string]any {
	return map[string]any{"status": "ok", "message": message, "data": map[string]any{}, "request_id": "req-uuid", "trace_id": "trace-id", "timestamp": "2026-05-09T00:00:00Z"}
}

func errorExample(code, message string) map[string]any {
	return map[string]any{"status": "error", "message": message, "error_code": code, "details": map[string]any{}, "path": "/v1/users/me", "request_id": "req-uuid", "trace_id": "trace-id", "timestamp": "2026-05-09T00:00:00Z"}
}

func healthDownExample() map[string]any {
	return map[string]any{"status": "down", "service": "user_service", "version": "v1.0.0", "environment": "development", "timestamp": "2026-05-09T00:00:00Z", "dependencies": map[string]any{"postgres": map[string]any{"status": "down", "latency_ms": 0.0, "error_code": "POSTGRES_UNAVAILABLE"}}}
}

func schemas() map[string]any {
	return map[string]any{
		"SuccessEnvelope": map[string]any{"type": "object", "required": []string{"status", "message", "data", "request_id", "trace_id", "timestamp"}},
		"ErrorEnvelope":   map[string]any{"type": "object", "required": []string{"status", "message", "error_code", "details", "path", "request_id", "trace_id", "timestamp"}},
	}
}
