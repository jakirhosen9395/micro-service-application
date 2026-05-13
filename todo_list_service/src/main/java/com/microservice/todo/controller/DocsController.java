package com.microservice.todo.controller;

import com.microservice.todo.config.TodoProperties;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class DocsController {
    private final TodoProperties properties;

    public DocsController(TodoProperties properties) {
        this.properties = properties;
    }

    @GetMapping(value = "/docs", produces = MediaType.TEXT_HTML_VALUE)
    public String docs() {
        return """
                <!doctype html>
                <html lang="en">
                <head>
                  <meta charset="utf-8" />
                  <meta name="viewport" content="width=device-width, initial-scale=1" />
                  <title>Todo List Service API Console</title>
                  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
                  <style>
                    body{margin:0;background:#f7f7fb;color:#111827;font-family:Inter,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
                    .guide{padding:24px 28px;background:#111827;color:#f9fafb;display:grid;gap:16px}
                    .guide h1{margin:0;font-size:28px}.guide p{margin:0;line-height:1.55;color:#d1d5db}.chips{display:flex;flex-wrap:wrap;gap:8px}.chip{background:#374151;border:1px solid #4b5563;border-radius:999px;padding:6px 10px;font-size:13px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px}.card{background:#1f2937;border:1px solid #374151;border-radius:14px;padding:14px}.card h2{font-size:16px;margin:0 0 8px}.card ol,.card ul{margin:0;padding-left:20px;color:#e5e7eb;line-height:1.55}.note{background:#fffbeb;color:#713f12;border-left:4px solid #f59e0b;padding:12px 16px;margin:0}.swagger-ui .topbar{display:none}#swagger-ui{background:#fff}
                  </style>
                </head>
                <body>
                  <section class="guide">
                    <h1>Todo List Service API Console</h1>
                    <div class="chips">
                      <span class="chip">Service: %s</span>
                      <span class="chip">Environment: %s</span>
                      <span class="chip">Version: %s</span>
                      <span class="chip">Base URL: same origin</span>
                    </div>
                    <div class="grid">
                      <div class="card"><h2>How to use</h2><ol><li>Start Auth service.</li><li>Login through Auth service <code>POST /v1/signin</code>.</li><li>Copy <code>access_token</code>.</li><li>Click <strong>Authorize</strong>.</li><li>Paste <code>Bearer &lt;access_token&gt;</code>.</li><li>Create a todo with <code>POST /v1/todos</code>.</li><li>List todos with <code>GET /v1/todos</code>.</li><li>Transition, complete, archive, restore, delete, and inspect history.</li></ol></div>
                      <div class="card"><h2>Authorization model</h2><ul><li>Owner can read and mutate own todos.</li><li>Approved admin can read and hard-delete.</li><li>Service/system role can perform privileged operations.</li><li>Local access-grant projection allows cross-user read/history without synchronous calls.</li><li>Missing or invalid token returns 401; insufficient permission returns 403.</li></ul></div>
                      <div class="card"><h2>Side effects</h2><ul><li>PostgreSQL is source of truth.</li><li>Redis caches records, lists, today/overdue, and history with TTL.</li><li>Kafka events are emitted through transactional outbox.</li><li>Incoming grant events are written through inbox idempotency.</li><li>S3 stores pretty JSON audit snapshots.</li><li>MongoDB stores structured logs; APM captures traces.</li></ul></div>
                      <div class="card"><h2>Important events</h2><ul><li>todo.created</li><li>todo.updated</li><li>todo.status_changed</li><li>todo.completed</li><li>todo.archived</li><li>todo.restored</li><li>todo.deleted</li><li>todo.hard_deleted</li><li>todo.audit.s3_written / todo.audit.s3_failed</li></ul></div>
                    </div>
                    <p class="note">Only <code>/hello</code>, <code>/health</code>, and <code>/docs</code> are public. The OpenAPI document is embedded in this page; <code>/openapi.json</code>, <code>/v3/api-docs</code>, <code>/swagger-ui/**</code>, and <code>/actuator/**</code> are not public API routes.</p>
                  </section>
                  <div id="swagger-ui"></div>
                  <pre id="fallback" style="display:none"></pre>
                  <script>
                    const spec = %s;
                    spec.servers = [{ url: window.location.origin, description: 'same-origin Todo service' }];
                  </script>
                  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
                  <script>
                    function uuidv4(){return crypto.randomUUID ? crypto.randomUUID() : 'req-' + Math.random().toString(16).slice(2) + Date.now();}
                    if (window.SwaggerUIBundle) {
                      window.ui = SwaggerUIBundle({
                        spec,
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
                          if (!req.headers['X-Request-ID']) req.headers['X-Request-ID'] = uuidv4();
                          if (!req.headers['X-Trace-ID']) req.headers['X-Trace-ID'] = uuidv4();
                          if (!req.headers['X-Correlation-ID']) req.headers['X-Correlation-ID'] = uuidv4();
                          return req;
                        }
                      });
                    } else {
                      const fallback = document.getElementById('fallback');
                      fallback.style.display='block';
                      fallback.textContent = JSON.stringify(spec, null, 2);
                    }
                  </script>
                </body>
                </html>
                """.formatted(escape(properties.getServiceName()), escape(displayEnvironment(properties.getEnv())), escape(properties.getServiceVersion()), openApiSpec());
    }

    private String openApiSpec() {
        String version = escape(properties.getServiceVersion());
        return """
                {
                  "openapi": "3.1.0",
                  "info": {
                    "title": "todo_list_service API",
                    "version": "%s",
                    "description": "Authenticated todo CRUD, status transitions, history, transactional outbox/inbox, Redis cache, S3 audit snapshots, MongoDB structured logs, and Elastic APM traces. Login through auth_service first and paste the Bearer JWT into Authorize."
                  },
                  "tags": [
                    {"name":"system","description":"Public service identity and dependency health."},
                    {"name":"todos","description":"Protected todo CRUD, status transitions, history, and deletion."}
                  ],
                  "components": {
                    "securitySchemes": {"bearerAuth": {"type": "http", "scheme": "bearer", "bearerFormat": "JWT"}},
                    "schemas": {
                      "SuccessEnvelope": {"type":"object","required":["status","message","data","request_id","trace_id","timestamp"],"properties":{"status":{"type":"string","example":"ok"},"message":{"type":"string","example":"todo created"},"data":{"type":"object"},"request_id":{"type":"string","example":"req-uuid"},"trace_id":{"type":"string","example":"trace-id"},"timestamp":{"type":"string","format":"date-time"}}},
                      "ErrorEnvelope": {"type":"object","required":["status","message","error_code","details","path","request_id","trace_id","timestamp"],"properties":{"status":{"type":"string","example":"error"},"message":{"type":"string","example":"Authentication required"},"error_code":{"type":"string","example":"UNAUTHORIZED"},"details":{"type":"object"},"path":{"type":"string","example":"/v1/todos"},"request_id":{"type":"string","example":"req-uuid"},"trace_id":{"type":"string","example":"trace-id"},"timestamp":{"type":"string","format":"date-time"}}},
                      "TodoCreateRequest": {"type":"object","required":["title"],"properties":{"title":{"type":"string","maxLength":255,"example":"Verify todo_list_service requirements"},"description":{"type":"string","example":"Write and review the requirements document."},"priority":{"type":"string","enum":["LOW","MEDIUM","HIGH","URGENT"],"default":"MEDIUM","example":"HIGH"},"due_date":{"type":"string","format":"date-time","example":"2026-05-10T18:00:00Z"},"tags":{"type":"array","items":{"type":"string"},"example":["work","microservice"]}}},
                      "TodoUpdateRequest": {"type":"object","properties":{"title":{"type":"string","maxLength":255},"description":{"type":"string"},"priority":{"type":"string","enum":["LOW","MEDIUM","HIGH","URGENT"]},"due_date":{"type":"string","format":"date-time"},"tags":{"type":"array","items":{"type":"string"}}}},
                      "TodoStatusChangeRequest": {"type":"object","required":["status"],"properties":{"status":{"type":"string","enum":["PENDING","IN_PROGRESS","COMPLETED","CANCELLED","ARCHIVED"],"example":"IN_PROGRESS"},"reason":{"type":"string","example":"Started work"}}},
                      "Todo": {"type":"object","properties":{"id":{"type":"string"},"user_id":{"type":"string"},"tenant":{"type":"string"},"title":{"type":"string"},"description":{"type":"string"},"status":{"type":"string"},"priority":{"type":"string"},"due_date":{"type":"string","format":"date-time"},"tags":{"type":"array","items":{"type":"string"}},"archived":{"type":"boolean"},"created_at":{"type":"string","format":"date-time"},"updated_at":{"type":"string","format":"date-time"},"s3_object_key":{"type":"string"}}}
                    },
                    "responses": {
                      "Unauthorized": {"description":"Missing, invalid, or expired Auth service JWT.","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ErrorEnvelope"}}}},
                      "Forbidden": {"description":"Valid JWT but insufficient permission, non-approved admin, tenant mismatch, or missing grant.","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ErrorEnvelope"}}}},
                      "NotFound": {"description":"Todo not found or not visible to caller.","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ErrorEnvelope"}}}},
                      "Conflict": {"description":"Invalid status transition or conflicting domain state.","content":{"application/json":{"schema":{"$ref":"#/components/schemas/ErrorEnvelope"}}}}
                    }
                  },
                  "paths": {
                    "/hello": {"get":{"tags":["system"],"security":[],"summary":"Service identity","description":"Returns service identity only. No dependency checks and no secrets.","responses":{"200":{"description":"Service is running"}}}},
                    "/health": {"get":{"tags":["system"],"security":[],"summary":"Dependency health","description":"Checks jwt, postgres, redis, kafka, s3, mongodb, apm, and elasticsearch using the canonical health shape.","responses":{"200":{"description":"All dependencies are healthy"},"503":{"description":"At least one dependency is down"}}}},
                    "/docs": {"get":{"tags":["system"],"security":[],"summary":"Embedded API console","responses":{"200":{"description":"Interactive Swagger UI with embedded OpenAPI spec"}}}},
                    "/v1/todos": {"post":{"tags":["todos"],"security":[{"bearerAuth":[]}],"summary":"Create todo","description":"Creates a todo owned by JWT sub. Side effects: PostgreSQL todo/history/outbox rows, Redis invalidation and record cache, S3 audit snapshot, MongoDB log, APM trace, and todo.created Kafka event through outbox.","requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/TodoCreateRequest"},"examples":{"work":{"value":{"title":"Verify todo_list_service requirements","description":"Write and review the requirements document.","priority":"HIGH","due_date":"2026-05-10T18:00:00Z","tags":["work","microservice"]}}}}}},"responses":{"201":{"description":"Todo created","content":{"application/json":{"schema":{"$ref":"#/components/schemas/SuccessEnvelope"}}}},"401":{"$ref":"#/components/responses/Unauthorized"},"403":{"$ref":"#/components/responses/Forbidden"}}},"get":{"tags":["todos"],"security":[{"bearerAuth":[]}],"summary":"List/search/filter todos","description":"Reads Redis first, then PostgreSQL on cache miss. Supports status, priority, tag, search, archived, due_after, due_before, include_deleted, page, size, and sort. include_deleted requires approved admin or service/system token.","parameters":[{"name":"status","in":"query","schema":{"type":"string","enum":["PENDING","IN_PROGRESS","COMPLETED","CANCELLED","ARCHIVED"]}},{"name":"priority","in":"query","schema":{"type":"string","enum":["LOW","MEDIUM","HIGH","URGENT"]}},{"name":"tag","in":"query","schema":{"type":"string"}},{"name":"search","in":"query","schema":{"type":"string"}},{"name":"archived","in":"query","schema":{"type":"boolean"}},{"name":"include_deleted","in":"query","schema":{"type":"boolean","default":false}},{"name":"page","in":"query","schema":{"type":"integer","default":0}},{"name":"size","in":"query","schema":{"type":"integer","default":20}},{"name":"sort","in":"query","schema":{"type":"string","example":"created_at,desc"}}],"responses":{"200":{"description":"Todo page"},"401":{"$ref":"#/components/responses/Unauthorized"},"403":{"$ref":"#/components/responses/Forbidden"}}}},
                    "/v1/todos/overdue": {"get":{"tags":["todos"],"security":[{"bearerAuth":[]}],"summary":"List overdue todos","description":"Returns active, non-deleted todos due before now. Uses Redis overdue cache and PostgreSQL fallback.","responses":{"200":{"description":"Overdue todos"},"401":{"$ref":"#/components/responses/Unauthorized"},"403":{"$ref":"#/components/responses/Forbidden"}}}},
                    "/v1/todos/today": {"get":{"tags":["todos"],"security":[{"bearerAuth":[]}],"summary":"List todos due today UTC","description":"Returns active todos due in the current UTC day. Uses Redis today cache and PostgreSQL fallback.","responses":{"200":{"description":"Today todos"},"401":{"$ref":"#/components/responses/Unauthorized"},"403":{"$ref":"#/components/responses/Forbidden"}}}},
                    "/v1/todos/{id}": {"get":{"tags":["todos"],"security":[{"bearerAuth":[]}],"summary":"Get todo","description":"Allowed for owner, approved admin, service/system role, or active local grant with todo:read scope.","parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string"}}],"responses":{"200":{"description":"Todo detail"},"401":{"$ref":"#/components/responses/Unauthorized"},"403":{"$ref":"#/components/responses/Forbidden"},"404":{"$ref":"#/components/responses/NotFound"}}},"put":{"tags":["todos"],"security":[{"bearerAuth":[]}],"summary":"Update todo fields","description":"Updates title, description, priority, due_date, and tags but not status. Writes history, outbox, S3 audit, MongoDB log, APM trace, and invalidates Redis caches.","parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string"}}],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/TodoUpdateRequest"}}}},"responses":{"200":{"description":"Todo updated"},"401":{"$ref":"#/components/responses/Unauthorized"},"403":{"$ref":"#/components/responses/Forbidden"},"404":{"$ref":"#/components/responses/NotFound"}}},"delete":{"tags":["todos"],"security":[{"bearerAuth":[]}],"summary":"Soft delete todo","description":"Sets deleted_at, writes todo.deleted event through outbox, writes S3 audit, logs to MongoDB, and invalidates Redis caches.","parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string"}}],"responses":{"200":{"description":"Todo soft-deleted"},"401":{"$ref":"#/components/responses/Unauthorized"},"403":{"$ref":"#/components/responses/Forbidden"},"404":{"$ref":"#/components/responses/NotFound"}}}},
                    "/v1/todos/{id}/status": {"patch":{"tags":["todos"],"security":[{"bearerAuth":[]}],"summary":"Change todo status","description":"Applies valid status transitions only. Invalid transition returns 409 TODO_INVALID_STATUS_TRANSITION. Writes history, outbox, S3 audit, MongoDB log, APM trace, and invalidates Redis caches.","parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string"}}],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/TodoStatusChangeRequest"}}}},"responses":{"200":{"description":"Status changed"},"401":{"$ref":"#/components/responses/Unauthorized"},"403":{"$ref":"#/components/responses/Forbidden"},"409":{"$ref":"#/components/responses/Conflict"}}}},
                    "/v1/todos/{id}/complete": {"post":{"tags":["todos"],"security":[{"bearerAuth":[]}],"summary":"Complete todo","description":"Changes status to COMPLETED and sets completed_at. Emits todo.completed through outbox and writes S3 audit snapshot.","parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string"}}],"responses":{"200":{"description":"Todo completed"},"401":{"$ref":"#/components/responses/Unauthorized"},"403":{"$ref":"#/components/responses/Forbidden"}}}},
                    "/v1/todos/{id}/archive": {"post":{"tags":["todos"],"security":[{"bearerAuth":[]}],"summary":"Archive todo","description":"Changes status to ARCHIVED, sets archived flags, emits todo.archived, writes S3 audit, and invalidates Redis caches.","parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string"}}],"responses":{"200":{"description":"Todo archived"},"401":{"$ref":"#/components/responses/Unauthorized"},"403":{"$ref":"#/components/responses/Forbidden"}}}},
                    "/v1/todos/{id}/restore": {"post":{"tags":["todos"],"security":[{"bearerAuth":[]}],"summary":"Restore todo","description":"Restores archived or soft-deleted todo, emits todo.restored, writes audit, and invalidates caches.","parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string"}}],"responses":{"200":{"description":"Todo restored"},"401":{"$ref":"#/components/responses/Unauthorized"},"403":{"$ref":"#/components/responses/Forbidden"}}}},
                    "/v1/todos/{id}/history": {"get":{"tags":["todos"],"security":[{"bearerAuth":[]}],"summary":"Get todo history","description":"Allowed for owner, approved admin, service/system, or local grant with todo:history:read/todo:read scope. Uses Redis history cache and PostgreSQL fallback.","parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string"}}],"responses":{"200":{"description":"Todo history"},"401":{"$ref":"#/components/responses/Unauthorized"},"403":{"$ref":"#/components/responses/Forbidden"}}}},
                    "/v1/todos/{id}/hard": {"delete":{"tags":["todos"],"security":[{"bearerAuth":[]}],"summary":"Hard delete todo","description":"Approved admin or service/system role only. Writes todo.hard_deleted audit/event before deleting service-owned todo and history rows.","parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string"}}],"responses":{"200":{"description":"Todo hard-deleted"},"401":{"$ref":"#/components/responses/Unauthorized"},"403":{"$ref":"#/components/responses/Forbidden"},"404":{"$ref":"#/components/responses/NotFound"}}}}
                  }
                }
                """.formatted(version);
    }

    private String escape(String value) {
        return value == null ? "" : value.replace("\\", "\\\\").replace("\"", "\\\"");
    }

    private String displayEnvironment(String env) {
        return switch (env == null ? "" : env.toLowerCase()) {
            case "dev", "development" -> "development";
            case "stage", "staging" -> "stage";
            case "prod", "production" -> "production";
            default -> env;
        };
    }
}
