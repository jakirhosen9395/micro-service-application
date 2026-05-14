# admin_service

`admin_service` is the .NET / ASP.NET Core control-plane service for the unified microservice application. It manages approved-admin workflows, admin registration decisions, cross-user access decisions, access grants, user-state command events, admin projections, audit records, and operational dashboards.

The service follows the same infrastructure style as the working `auth_service`: env-driven configuration, fail-fast validation, PostgreSQL migrations, transactional outbox, Kafka inbox idempotency, Redis cache/locks, S3 audit snapshots, MongoDB structured logs, Elastic APM, Elasticsearch health visibility, and embedded Swagger UI at `/docs`.

## Runtime stack

- .NET 10 / ASP.NET Core minimal APIs
- PostgreSQL via EF Core / Npgsql
- Redis via StackExchange.Redis
- Kafka via Confluent.Kafka
- S3 / MinIO via AWSSDK.S3
- MongoDB structured logging via MongoDB.Driver
- Elastic APM with detailed HTTP/background transactions, dependency spans, errors, metrics, correlated logs, and Elasticsearch health checks
- Docker container port `8080`

## Elastic APM coverage

The service sends 100% sampled APM telemetry to `ADMIN_APM_SERVER_URL` using Elastic APM. Each HTTP transaction is enriched with request, tenant, user, route, status, duration, trace, and correlation identifiers. Background Kafka consumption, outbox publishing, and startup initialization are captured as APM transactions too.

Dependency visibility is emitted with named spans for PostgreSQL/EF, Redis, Kafka, S3/MinIO, MongoDB, APM Server, and Elasticsearch health checks. Errors are captured into APM and written as structured ECS-style JSON logs with `trace.id`, `transaction.id`, `span.id`, `error.*`, request metadata, user metadata, and redacted custom fields.

`ADMIN_APM_CAPTURE_BODY=all` is enabled in the environment files so transaction request bodies are available in APM. Elastic Agent or another log shipper should collect container stdout for the Kibana Logs, Infrastructure, Alerts, and Dashboard views.

## Public routes

Only these routes are public and unauthenticated:

| Method | Path | Purpose |
|---|---|---|
| GET | `/hello` | Lightweight service identity check. |
| GET | `/health` | Dependency health check. |
| GET | `/docs` | Embedded Swagger UI with Bearer JWT support. |

Routes such as `/`, `/live`, `/ready`, `/healthy`, `/openapi.json`, `/swagger`, `/redoc`, `/swagger/index.html`, and `/swagger/v1/swagger.json` are intentionally not exposed and should return `404`.

## Protected API catalog

Every `/v1/admin/**` endpoint requires a valid `auth_service` JWT with:

```text
role=admin
admin_status=approved
tenant=<ADMIN_TENANT>
iss=auth
aud=micro-app
```

Base path: `/v1/admin`

| Method | Path | Purpose |
|---|---|---|
| GET | `/dashboard` | Admin dashboard counts and recent audit. |
| GET | `/summary` | Admin summary grouped by status. |
| GET | `/registrations` | List admin registration requests. |
| GET | `/registrations/{requestId}` | Get one admin registration request. |
| POST | `/registrations/{requestId}/approve` | Approve admin registration. |
| POST | `/registrations/{requestId}/reject` | Reject admin registration. |
| GET | `/access-requests` | List cross-user access requests. |
| GET | `/access-requests/{requestId}` | Get one cross-user access request. |
| POST | `/access-requests/{requestId}/approve` | Approve access request and create a grant. |
| POST | `/access-requests/{requestId}/reject` | Reject access request. |
| GET | `/access-grants` | List access grants. |
| GET | `/access-grants/{grantId}` | Get one access grant. |
| POST | `/access-grants/{grantId}/revoke` | Revoke an active grant. |
| GET | `/users` | List user projections. |
| GET | `/users/{userId}` | Get one user projection. |
| GET | `/users/{userId}/activity` | Get user-related admin audit activity. |
| GET | `/users/{userId}/access-grants` | Get user-related access grants. |
| GET | `/users/{userId}/reports` | Get user report projections. |
| POST | `/users/{userId}/suspend` | Validate user projection and emit suspend command. |
| POST | `/users/{userId}/activate` | Validate user projection and emit activate command. |
| POST | `/users/{userId}/force-password-reset` | Validate user projection and emit force-password-reset command. |
| GET | `/calculations` | List calculation projections. |
| GET | `/calculations/{calculationId}` | Get one calculation projection. |
| GET | `/calculations/users/{userId}` | List calculation projections for a user. |
| GET | `/calculations/summary` | Calculation summary. |
| GET | `/todos` | List todo projections. |
| GET | `/todos/{todoId}` | Get one todo projection. |
| GET | `/todos/users/{userId}` | List todo projections for a user. |
| GET | `/todos/summary` | Todo summary. |
| POST | `/reports` | Request an admin report by event. |
| GET | `/reports` | List report projections. |
| GET | `/reports/{reportId}` | Get one report projection. |
| GET | `/reports/users/{userId}` | List report projections for a user. |
| GET | `/reports/summary` | Report summary. |
| POST | `/reports/{reportId}/cancel` | Request report cancellation by event. |
| GET | `/audit` | List admin audit events. |
| GET | `/audit/{eventId}` | Get one audit event. |

Decision payload:

```json
{
  "reason": "Verified request"
}
```

Access approval payload:

```json
{
  "scope": "calculator:history:read",
  "expires_at": "2030-01-01T00:00:00Z",
  "reason": "Approved for support investigation"
}
```

Admin report payload:

```json
{
  "report_type": "calculator_history_report",
  "target_user_id": "optional-target-user-id",
  "format": "pdf",
  "date_from": "2026-05-01",
  "date_to": "2026-05-09",
  "filters": {},
  "options": {}
}
```

Allowed report formats: `pdf`, `xlsx`, `csv`, `json`, `html`.

## Current fixes in this package

This package includes the latest admin service fixes:

- `.env.dev`, `.env.stage`, `.env.prod`, and `.env.example` have identical keys and order.
- Environment files point to infrastructure host `192.168.56.100`.
- Docker healthcheck sends `X-Forwarded-Proto: https`, so stage/prod health works when HTTPS enforcement is enabled.
- `command.sh` keeps Auth-style simple build/run behavior but does not fail when old containers/images are absent.
- `/docs` embeds the OpenAPI document and does not expose `/openapi.json` publicly.
- Swagger uses relative server URL `/`, so Try-it-out calls the current browser host/port.
- Swagger includes a Bearer JWT helper and request interceptor for `Authorization`, `X-Request-ID`, `X-Trace-ID`, and `X-Correlation-ID`.
- Admin user command APIs validate `admin_user_projection` before emitting events; missing users return `404` instead of emitting commands.
- Added expanded Admin compatibility APIs for user dashboard/preferences/security/RBAC/effective permissions, calculation failed/history-cleared/user summaries, todo overdue/today/archive/deleted/history/audit, and report types/metadata/progress/events/files/preview/download-info/retry/regenerate/templates/schedules/queue/audit.
- Kafka consumer ignores tenant mismatches and duplicate inbox rows safely.
- Kafka projection handlers read nested `user` payloads from `auth_service` events so user/admin projections are populated correctly.
- Redis deserialization is compatible with .NET 10.

## Build and run

Build one image:

```bash
docker build -t admin_service:dev .
```

Run one environment:

```bash
docker run -d --name admin_service_dev --env-file .env.dev -p 1010:8080 admin_service:dev
```

Run all three with the helper script:

```bash
chmod +x command.sh
./command.sh
```

Default host-port mapping used by `command.sh`:

| Environment | Container | Host URL |
|---|---|---|
| dev | `admin_service_dev` | `http://localhost:1010` |
| stage | `admin_service_stage` | `http://localhost:1011` |
| prod | `admin_service_prod` | `http://localhost:1012` |

The container always listens on port `8080`.

## Healthcheck note for stage/prod

Stage and production env files enable:

```dotenv
ADMIN_SECURITY_REQUIRE_HTTPS=true
ADMIN_SECURITY_SECURE_COOKIES=true
```

The Docker healthcheck uses plain in-container HTTP, but sends:

```text
X-Forwarded-Proto: https
```

This lets the app treat the healthcheck as HTTPS while still listening on `8080` inside Docker.

## Smoke testing

Use matching Admin/Auth environments:

```bash
# dev
./tests/admin_service_api_smoke_test.sh 192.168.56.50 1010 192.168.56.50 6060

# stage
./tests/admin_service_api_smoke_test.sh 192.168.56.50 1011 192.168.56.50 6061

# prod
./tests/admin_service_api_smoke_test.sh 192.168.56.50 1012 192.168.56.50 6062
```

Do not test `admin_service_dev` with an `auth_service_prod` token when tenant matching is enabled; dev expects `tenant=dev`, stage expects `tenant=stage`, and prod expects `tenant=prod`.

## Local contract checks

The test project contains static contract tests for:

- env key order and forbidden infra toggles
- Dockerfile container port and `/hello` healthcheck
- canonical outbox/inbox migration DDL

Run when the .NET SDK is installed:

```bash
dotnet test
```

## Files and schemas

Primary PostgreSQL schema: `admin`

Core tables:

```text
admin_profiles
admin_registration_requests
admin_access_requests
admin_access_grants
admin_user_projection
admin_calculation_projection
admin_todo_projection
admin_report_projection
admin_audit_events
outbox_events
kafka_inbox_events
```

Kafka topics used:

```text
auth.events
auth.admin.requests
auth.admin.decisions
admin.events
user.events
calculator.events
todo.events
report.events
access.events
admin_service.dead-letter
```

S3 audit key format:

```text
admin_service/<environment>/tenant/<tenant>/users/<actor_user_id>/events/<yyyy>/<MM>/<dd>/<HHmmss>_<event_type_slug>_<event_id>.json
```

Redis key namespace:

```text
<environment>:admin_service:<purpose>:<id>
```

MongoDB log collection:

```text
admin_service_<environment>_logs
```
