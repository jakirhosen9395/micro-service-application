# admin_service

`admin_service` is the ASP.NET Core control-plane service for the unified microservice application. This rewrite is intentionally scoped to the admin service only. It implements approved-admin authorization, admin registration decisions, cross-user access decisions, user-state command events, admin projections, transactional outbox, Kafka inbox idempotency, S3 audit snapshots, MongoDB structured logs, and contract-shaped `/hello`, `/health`, and `/docs` endpoints.

The service follows the canonical build contract in the uploaded specification: container port `8080`, public unauthenticated routes limited to `GET /hello`, `GET /health`, and `GET /docs`, every business API under `/v1/admin/**`, local JWT validation against `auth_service` tokens, PostgreSQL schema `admin`, Redis cache/locks, Kafka outbox/inbox, MinIO/S3 audit objects, MongoDB log documents, and Elastic APM/Elasticsearch health visibility.

## What this service owns

`admin_service` owns:

- Approved admin authorization enforcement.
- Admin dashboard and summary views.
- Admin registration approval/rejection workflow.
- Cross-user access request approval/rejection workflow.
- Cross-user access grant creation and revocation.
- User suspend, activate, and force-password-reset command events.
- Local admin projections for users, calculations, todos, and reports.
- Admin audit records and S3 audit snapshots.

It does **not** issue JWTs, hash passwords, or call other services synchronously. Identity remains owned by `auth_service`; cross-service state reaches this service through Kafka events and local projections.

## Runtime stack

- .NET 8 / ASP.NET Core minimal API
- EF Core with PostgreSQL / Npgsql
- Redis through `StackExchange.Redis`
- Kafka through `Confluent.Kafka`
- S3/MinIO through `AWSSDK.S3`
- MongoDB structured logs through `MongoDB.Driver`
- Swagger UI at `/docs` with embedded OpenAPI spec and bearer auth security

## Repository layout

```text
admin_service/
  .env.dev
  .env.stage
  .env.prod
  .env.example
  Dockerfile
  command.sh
  README.md
  migrations/
    001_initial_admin_schema.sql
  src/
    AdminService.Api/
      Configuration/
      Contracts/
      Docs/
      Domain/
      Endpoints/
      Http/
      Infrastructure/
      Middleware/
      Persistence/
      Security/
      Program.cs
  tests/
    AdminService.Tests/
```

## Environment files

All four env files use the same keys in the same order:

- `.env.dev`
- `.env.stage`
- `.env.prod`
- `.env.example`

The generated `.env.dev`, `.env.stage`, and `.env.prod` files use the infrastructure endpoint `192.168.56.200` and the credentials supplied with the request. The README intentionally does not print secret values. The service validates every required key on startup and fails fast when a key is missing or contract-critical values are wrong.

Important contract values:

```dotenv
ADMIN_SERVICE_NAME=admin_service
ADMIN_PORT=8080
ADMIN_JWT_ISSUER=auth
ADMIN_JWT_AUDIENCE=micro-app
ADMIN_JWT_ALGORITHM=HS256
ADMIN_POSTGRES_SCHEMA=admin
ADMIN_KAFKA_EVENTS_TOPIC=admin.events
ADMIN_KAFKA_DEAD_LETTER_TOPIC=admin_service.dead-letter
ADMIN_S3_BUCKET=microservice
ADMIN_MONGO_DATABASE=db_micro_services
ADMIN_LOG_FORMAT=pretty-json
ADMIN_LOGSTASH_ENABLED=false
```

No infrastructure enable/disable gates are used. The only explicit disabled toggle is `ADMIN_LOGSTASH_ENABLED=false`, as required by the contract.

## Build and run

From the `admin_service` root:

```bash
docker build -t admin_service:dev .
docker run --name admin_service_dev --env-file .env.dev -p 8080:8080 admin_service:dev
```

Or use the helper script:

```bash
chmod +x command.sh
./command.sh dev
```

Stage and production use the same internal container port:

```bash
docker build -t admin_service:stage .
docker run --name admin_service_stage --env-file .env.stage -p 8080:8080 admin_service:stage

docker build -t admin_service:prod .
docker run --name admin_service_prod --env-file .env.prod -p 8080:8080 admin_service:prod
```

Only one container can bind host port `8080` at a time. When running all services locally, keep container port `8080` but map distinct host ports in Compose/Kubernetes.

## Startup sequence

On startup the service:

1. Loads `.env.<environment>` when environment variables are not already provided.
2. Validates all required `ADMIN_*` keys.
3. Configures pretty JSON logging and MongoDB log writing.
4. Configures request context propagation: request ID, trace ID, correlation ID, tenant, and user ID.
5. Connects to PostgreSQL.
6. Applies `migrations/001_initial_admin_schema.sql` to schema `admin`.
7. Connects to Redis and verifies ping.
8. Creates/verifies Kafka topics and starts outbox and consumer workers.
9. Verifies or creates the S3 bucket `microservice`.
10. Verifies MongoDB and creates canonical log indexes.
11. Checks APM and Elasticsearch availability for health visibility.
12. Registers `/hello`, `/health`, `/docs`, and protected `/v1/admin/**` routes.
13. Emits `application.started` as pretty JSON and MongoDB structured log.

PostgreSQL, Redis, Kafka, S3, and MongoDB startup failures stop the service. APM and Elasticsearch failures are reflected in `/health` as `down`.

## Public routes

Only these routes are public and unauthenticated:

| Method | Path      | Purpose                                       |
| ------ | --------- | --------------------------------------------- |
| GET    | `/hello`  | Service identity check. No dependency checks. |
| GET    | `/health` | Dependency health check.                      |
| GET    | `/docs`   | Swagger UI with bearer JWT security.          |

Rejected routes such as `/`, `/live`, `/ready`, and `/healthy` are not mapped and return `404`.

## Authentication and authorization

Every `/v1/admin/**` route requires a valid `auth_service` JWT. The service validates the token locally using the shared `ADMIN_JWT_SECRET`, issuer, audience, HS256 algorithm, and configured leeway.

Required claims:

```json
{
  "iss": "auth",
  "aud": "micro-app",
  "sub": "user-uuid",
  "jti": "token-id",
  "username": "admin",
  "email": "admin@example.com",
  "role": "admin",
  "admin_status": "approved",
  "tenant": "dev",
  "iat": 1710000000,
  "nbf": 1710000000,
  "exp": 1710000900
}
```

Admin authorization requires:

- Token is valid and unexpired.
- `role=admin`.
- `admin_status=approved`.
- `status=active` when the token contains a status claim.
- `tenant` matches `ADMIN_TENANT` when tenant matching is enabled.

Missing or invalid tokens return `401`. Valid tokens without approved admin permissions return `403`.

## Response envelope

Successful business responses use:

```json
{
  "status": "ok",
  "message": "resource loaded",
  "data": {},
  "request_id": "req-uuid",
  "trace_id": "trace-id",
  "timestamp": "2026-05-09T00:00:00.000Z"
}
```

Errors use:

```json
{
  "status": "error",
  "message": "Authentication required",
  "error_code": "UNAUTHORIZED",
  "details": {},
  "path": "/v1/admin/example",
  "request_id": "req-uuid",
  "trace_id": "trace-id",
  "timestamp": "2026-05-09T00:00:00.000Z"
}
```

## API catalog

Base path: `/v1/admin`

All endpoints below require an approved admin JWT.

### Dashboard

| Method | Path                  |
| ------ | --------------------- |
| GET    | `/v1/admin/dashboard` |
| GET    | `/v1/admin/summary`   |

### Admin registration decisions

| Method | Path                                          |
| ------ | --------------------------------------------- |
| GET    | `/v1/admin/registrations`                     |
| GET    | `/v1/admin/registrations/{requestId}`         |
| POST   | `/v1/admin/registrations/{requestId}/approve` |
| POST   | `/v1/admin/registrations/{requestId}/reject`  |

Decision payload:

```json
{
  "reason": "Verified request"
}
```

Approving a registration creates/updates `admin_profiles`, updates the user projection, writes an audit event, writes an S3 audit snapshot, and emits a canonical Kafka event to `auth.admin.decisions`.

### Access requests and grants

| Method | Path                                            |
| ------ | ----------------------------------------------- |
| GET    | `/v1/admin/access-requests`                     |
| GET    | `/v1/admin/access-requests/{requestId}`         |
| POST   | `/v1/admin/access-requests/{requestId}/approve` |
| POST   | `/v1/admin/access-requests/{requestId}/reject`  |
| GET    | `/v1/admin/access-grants`                       |
| GET    | `/v1/admin/access-grants/{grantId}`             |
| POST   | `/v1/admin/access-grants/{grantId}/revoke`      |

Access approval payload:

```json
{
  "scope": "calculator:history:read",
  "expires_at": "2030-01-01T00:00:00Z",
  "reason": "Approved for support investigation"
}
```

Approving an access request creates `admin_access_grants` and emits `access.request.approved` plus `access.grant.created` to `access.events`.

### Users

| Method | Path                                            |
| ------ | ----------------------------------------------- |
| GET    | `/v1/admin/users`                               |
| GET    | `/v1/admin/users/{userId}`                      |
| GET    | `/v1/admin/users/{userId}/activity`             |
| GET    | `/v1/admin/users/{userId}/access-grants`        |
| GET    | `/v1/admin/users/{userId}/reports`              |
| POST   | `/v1/admin/users/{userId}/suspend`              |
| POST   | `/v1/admin/users/{userId}/activate`             |
| POST   | `/v1/admin/users/{userId}/force-password-reset` |

User state commands do not call `auth_service`; they emit command events to `admin.events` for downstream consumers.

### Calculation projections

| Method | Path                                     |
| ------ | ---------------------------------------- |
| GET    | `/v1/admin/calculations`                 |
| GET    | `/v1/admin/calculations/{calculationId}` |
| GET    | `/v1/admin/calculations/users/{userId}`  |
| GET    | `/v1/admin/calculations/summary`         |

### Todo projections

| Method | Path                             |
| ------ | -------------------------------- |
| GET    | `/v1/admin/todos`                |
| GET    | `/v1/admin/todos/{todoId}`       |
| GET    | `/v1/admin/todos/users/{userId}` |
| GET    | `/v1/admin/todos/summary`        |

### Report projections and admin report requests

| Method | Path                                  |
| ------ | ------------------------------------- |
| POST   | `/v1/admin/reports`                   |
| GET    | `/v1/admin/reports`                   |
| GET    | `/v1/admin/reports/{reportId}`        |
| GET    | `/v1/admin/reports/users/{userId}`    |
| GET    | `/v1/admin/reports/summary`           |
| POST   | `/v1/admin/reports/{reportId}/cancel` |

Report request payload:

```json
{
  "report_type": "calculator_history_report",
  "target_user_id": "optional-user-id",
  "format": "pdf",
  "date_from": "2026-05-01",
  "date_to": "2026-05-09",
  "filters": {},
  "options": {}
}
```

Allowed formats: `pdf`, `csv`, `json`, `html`, `xlsx`.

### Audit

| Method | Path                        |
| ------ | --------------------------- |
| GET    | `/v1/admin/audit`           |
| GET    | `/v1/admin/audit/{eventId}` |

## PostgreSQL schema

The service uses schema `admin`. The migration creates:

- `admin_profiles`
- `admin_registration_requests`
- `admin_access_requests`
- `admin_access_grants`
- `admin_user_projection`
- `admin_calculation_projection`
- `admin_todo_projection`
- `admin_report_projection`
- `admin_audit_events`
- `outbox_events`
- `kafka_inbox_events`

`outbox_events` and `kafka_inbox_events` use the canonical contract and live inside the `admin` schema, not `public`.

## Kafka behavior

The service publishes only committed outbox events. Business mutations write domain state and outbox rows in the same PostgreSQL transaction. The background publisher later sends those events to Kafka and marks rows as `SENT`, `FAILED`, or `DEAD_LETTERED`.

Primary outgoing topics:

- `admin.events` for admin commands, report requests, and audit-relevant admin events.
- `auth.admin.decisions` for admin registration approval/rejection decisions.
- `access.events` for access request and grant lifecycle events.
- `admin_service.dead-letter` for failed event handling conventions.

The consumer subscribes to the canonical topic list and updates local projections idempotently through `kafka_inbox_events`.

## S3 audit snapshot path

Audit snapshots are written as pretty JSON under:

```text
s3://microservice/admin_service/<environment>/tenant/<tenant>/users/<actor_user_id>/events/<yyyy>/<MM>/<dd>/<HHmmss>_<event_type_slug>_<event_id>.json
```

No passwords, JWTs, refresh tokens, authorization headers, access keys, or connection strings are included in audit payloads.

## MongoDB logging

Logs are written to database `db_micro_services` and collection:

```text
admin_service_<environment>_logs
```

The logger creates indexes for timestamp, level, event, request ID, trace ID, user ID, path/status, and error code. Successful `/hello`, `/health`, and `/docs` requests are suppressed by default.

## Health contract

`GET /health` returns the canonical dependency keys:

```json
{
  "status": "ok",
  "service": "admin_service",
  "version": "v1.0.0",
  "environment": "development",
  "timestamp": "2026-05-09T00:00:00.000Z",
  "dependencies": {
    "jwt": { "status": "ok", "latency_ms": 0.0 },
    "postgres": { "status": "ok", "latency_ms": 2.4 },
    "redis": { "status": "ok", "latency_ms": 1.1 },
    "kafka": { "status": "ok", "latency_ms": 4.9 },
    "s3": { "status": "ok", "latency_ms": 6.2 },
    "mongodb": { "status": "ok", "latency_ms": 3.1 },
    "apm": { "status": "ok", "latency_ms": 0.2 },
    "elasticsearch": { "status": "ok", "latency_ms": 8.7 }
  }
}
```

When a dependency fails, `/health` returns `503` with top-level `status=down` and a dependency-specific `error_code`. Secret values are never included.

## Local checks

Run unit/contract tests:

```bash
dotnet test tests/AdminService.Tests/AdminService.Tests.csproj
```

Build the API project locally:

```bash
dotnet build src/AdminService.Api/AdminService.Api.csproj
```

Run locally without Docker:

```bash
ADMIN_ENV_FILE=.env.dev dotnet run --project src/AdminService.Api/AdminService.Api.csproj
```

Smoke test:

```bash
curl -i http://localhost:8080/hello
curl -i http://localhost:8080/health
curl -i http://localhost:8080/docs
curl -i http://localhost:8080/live
```

`/live` should return `404`.

## Security notes

- This service validates auth-service JWTs locally; it never calls auth-service synchronously.
- It does not hash or store passwords.
- It never writes JWTs, authorization headers, passwords, access keys, secret keys, or connection passwords to logs, Kafka payloads, health responses, or S3 audit snapshots.
- Every mutation writes an audit record and a canonical event envelope.
- Redis locks protect decision endpoints against duplicate approvals/rejections.

## Operational troubleshooting

- If startup fails before serving traffic, inspect the pretty JSON `application.starting`, `migration.*`, `kafka.topics.*`, `s3.*`, or `mongodb.*` logs.
- If `/health` is `503`, check the dependency key with `status=down`; the error code intentionally excludes secrets.
- If a projection is missing, check `admin.kafka_inbox_events` for `FAILED` rows and the MongoDB log collection for `kafka.inbox.projection_failed`.
- If events are not leaving the service, check `admin.outbox_events` for old `PENDING`, `FAILED`, or `DEAD_LETTERED` rows.
- If an access decision is rejected as duplicate, wait for the Redis lock TTL or inspect the original decision result.
