# report_service

Production-grade asynchronous report generation service for the unified microservice application.

`report_service` owns report type registration, dataset selection from local projections, report request lifecycle, BullMQ job execution, progress tracking, multi-format rendering, S3/MinIO storage, templates, schedules, audit events, Kafka outbox/inbox, Redis caches, MongoDB structured logs, and Elastic APM/Elasticsearch health.

It does **not** own authentication, user signup, admin approval, calculator execution, todo CRUD, or synchronous calls to other services during generation.

## Runtime and tooling

| Area | Tooling |
|---|---|
| Runtime | Node.js `>=24 <25`, ESM only |
| HTTP | Fastify 5.x |
| Validation | Zod 4.x |
| Queue | BullMQ 5.x + ioredis 5.x |
| Database | PostgreSQL schema `report` |
| Events | KafkaJS + transactional outbox/inbox |
| Object storage | S3/MinIO bucket `microservice` |
| Logs | MongoDB database `micro_services_logs` |
| Observability | Elastic APM, Elasticsearch, Kibana |
| Build/test | TypeScript 6.x, tsup, tsx, Vitest |

## Public route contract

Only these unauthenticated endpoints are public:

```text
GET /hello
GET /health
GET /docs
```

All business APIs are under `/v1/reports/**` and require a valid Auth service JWT.

The service intentionally does not expose public raw docs routes such as `/openapi.json`, `/v3/api-docs`, `/swagger-ui/**`, `/documentation/json`, `/redoc`, `/metrics`, `/actuator`, `/live`, `/ready`, or `/healthy`.

## Build and run

```bash
npm install
npm run check
npm test
npm run build
```

Docker:

```bash
docker build -t report_service:dev .
docker run --name report_service_dev --env-file .env.dev -p 5050:8080 report_service:dev
```

Fixed local multi-environment script:

```bash
chmod +x command.sh
./command.sh
```

`command.sh` starts:

| Environment | Container | Host port | Container port |
|---|---|---:|---:|
| dev | `report_service_dev` | `5050` | `8080` |
| stage | `report_service_stage` | `5051` | `8080` |
| prod | `report_service_prod` | `5052` | `8080` |

## Environment contract

The service includes:

```text
.env.dev
.env.stage
.env.prod
.env.example
```

All four files have identical keys and order. Infrastructure is always initialized. Forbidden infrastructure toggles such as `REPORT_S3_ENABLED`, `REPORT_KAFKA_ENABLED`, `REPORT_REDIS_ENABLED`, `REPORT_POSTGRES_ENABLED`, `REPORT_MONGO_ENABLED`, `REPORT_APM_ENABLED`, and `REPORT_SWAGGER_ENABLED` are rejected. The only allowed disabled integration flag is:

```dotenv
REPORT_LOGSTASH_ENABLED=false
```

Required canonical values include:

```dotenv
REPORT_SERVICE_NAME=report_service
REPORT_PORT=8080
REPORT_JWT_ISSUER=auth
REPORT_JWT_AUDIENCE=micro-app
REPORT_JWT_ALGORITHM=HS256
REPORT_POSTGRES_SCHEMA=report
REPORT_KAFKA_EVENTS_TOPIC=report.events
REPORT_KAFKA_DEAD_LETTER_TOPIC=report.dead-letter
REPORT_S3_BUCKET=microservice
REPORT_LOG_FORMAT=pretty-json
REPORT_BULLMQ_QUEUE_NAME=report-generation
```

## API catalog

### System

| Method | Path | Auth |
|---|---|---:|
| GET | `/hello` | No |
| GET | `/health` | No |
| GET | `/docs` | No |

### Reports

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/reports/types` | List report types. |
| GET | `/v1/reports/types/{reportType}` | Get one report type. |
| POST | `/v1/reports` | Request asynchronous report. |
| GET | `/v1/reports` | List caller report requests. |
| GET | `/v1/reports/{reportId}` | Get report status. |
| POST | `/v1/reports/{reportId}/cancel` | Cancel queued/processing report. |
| POST | `/v1/reports/{reportId}/retry` | Retry failed report. |
| POST | `/v1/reports/{reportId}/regenerate` | Alias for retry/regeneration. |
| DELETE | `/v1/reports/{reportId}` | Soft delete report. |
| GET | `/v1/reports/{reportId}/metadata` | Get completed report metadata. |
| GET | `/v1/reports/{reportId}/download` | Stream S3 report file. |
| GET | `/v1/reports/{reportId}/preview` | Preview JSON/CSV/HTML or safe binary metadata. |
| GET | `/v1/reports/{reportId}/progress` | Get current progress. |
| GET | `/v1/reports/{reportId}/events` | Get progress event timeline. |
| GET | `/v1/reports/{reportId}/files` | List generated files. |

### Templates

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/reports/templates` | List templates. |
| GET | `/v1/reports/templates/{templateId}` | Get template. |
| POST | `/v1/reports/templates` | Create safe template. |
| PUT | `/v1/reports/templates/{templateId}` | Update template. |
| POST | `/v1/reports/templates/{templateId}/activate` | Activate template. |
| POST | `/v1/reports/templates/{templateId}/deactivate` | Deactivate template. |

Templates are safe JSON/text configurations. They allow title, section order, visible columns, labels, logo text, footer text, and simple styling. They do not execute user JavaScript.

### Schedules

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/reports/schedules` | List schedules. |
| GET | `/v1/reports/schedules/{scheduleId}` | Get schedule. |
| POST | `/v1/reports/schedules` | Create schedule. |
| PUT | `/v1/reports/schedules/{scheduleId}` | Update schedule. |
| POST | `/v1/reports/schedules/{scheduleId}/pause` | Pause schedule. |
| POST | `/v1/reports/schedules/{scheduleId}/resume` | Resume schedule. |
| DELETE | `/v1/reports/schedules/{scheduleId}` | Soft delete schedule. |

Schedules are persisted in PostgreSQL and emit Kafka/audit events. The current scheduler mode initializes consistently and is ready for BullMQ repeatable execution integration.

### Observability

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/reports/queue/summary` | BullMQ queue counts for approved admin/service/system. |
| GET | `/v1/reports/audit` | List report audit events. |
| GET | `/v1/reports/audit/{eventId}` | Get one audit event. |

## Request example

```json
{
  "report_type": "calculator_history_report",
  "target_user_id": "optional-target-user-id",
  "format": "pdf",
  "date_from": "2026-05-01",
  "date_to": "2026-05-09",
  "filters": {},
  "options": {
    "include_summary": true,
    "include_charts": true,
    "include_raw_data": false,
    "timezone": "Asia/Dhaka",
    "locale": "en",
    "title": "My Report"
  }
}
```

Validation rules:

- `report_type` is required.
- `format` defaults to the report type default.
- `date_from` and `date_to` must be valid `YYYY-MM-DD` dates.
- `date_from <= date_to`.
- `target_user_id` defaults to JWT `sub`.
- filters must match the report type allowed filter keys.
- `format` must be allowed by the selected report type.
- target user access must be authorized locally from JWT role/status or local access-grant projections.

## Report types

Implemented report types:

```text
calculator_history_report
todo_summary_report
user_activity_report
full_user_report
user_profile_report
user_dashboard_report
user_access_grants_report
cross_user_access_report
admin_decision_report
admin_audit_report
calculator_summary_report
calculator_operations_report
todo_activity_report
todo_status_report
productivity_summary_report
full_application_activity_report
report_inventory_report
report_generation_health_report
```

Every report type declares:

```text
report_type
name
description
allowed_formats
default_format
source_projections
filters_schema
options_schema
required_scopes
owner_access_policy
default_sort
max_rows
preview_supported_formats
```

Allowed formats:

```text
pdf | xlsx | csv | json | html
```

## Authorization

JWT validation is local. Required claims:

```text
iss, aud, sub, jti, username, email, role, admin_status, tenant, iat, nbf, exp
```

Roles:

```text
user | admin | service | system
```

Admin statuses:

```text
not_requested | pending | approved | rejected | suspended
```

Rules:

- Users may request and read their own reports.
- Approved admins may request and read target-user reports.
- Service/system roles may request and read target-user reports.
- Cross-user users require active grants from `report.report_access_grant_projection` populated by Kafka `access.events`.
- Tenant mismatch returns `403`.
- Missing/invalid/expired token returns `401`.
- Valid token without permission returns `403`.

## Lifecycle

```text
POST /v1/reports
  -> validate JWT, tenant, target access, report type, format, filters
  -> insert report.report_requests as QUEUED
  -> insert report.report_generation_jobs as QUEUED
  -> insert progress event queued
  -> insert report.requested into report.outbox_events
  -> enqueue BullMQ job with report_id as jobId
  -> write S3 audit snapshot

worker
  -> mark PROCESSING
  -> load local PostgreSQL projections only
  -> update progress loading_data/rendering/uploading
  -> render JSON/CSV/HTML/PDF/XLSX
  -> upload report file to S3
  -> insert report.report_files metadata and checksum
  -> mark COMPLETED or FAILED
  -> insert outbox event
  -> write S3 audit snapshot
  -> invalidate Redis caches
```

## PostgreSQL schema

All database objects live in schema `report`.

Required tables:

```text
report_requests
report_files
report_templates
report_schedules
report_generation_jobs
report_audit_events
report_user_projection
report_calculation_projection
report_todo_projection
report_access_grant_projection
report_admin_decision_projection
report_activity_projection
outbox_events
kafka_inbox_events
```

Additional tables:

```text
report_progress_events
report_share_links
report_dataset_snapshots
```

The migration uses canonical outbox and inbox DDL and fixes the previous duplicate `aggregate_type` bug.

## Kafka

Publishes through transactional outbox only:

```text
report.events
```

Dead letter topic:

```text
report.dead-letter
```

Consumes:

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
```

Outgoing events include:

```text
report.requested
report.processing
report.progress_updated
report.completed
report.failed
report.cancelled
report.retry_requested
report.deleted
report.downloaded
report.previewed
report.template.created
report.template.updated
report.template.activated
report.template.deactivated
report.schedule.created
report.schedule.updated
report.schedule.paused
report.schedule.resumed
report.schedule.deleted
report.audit.s3_written
report.audit.s3_failed
```

Kafka envelope fields:

```json
{
  "event_id": "evt-uuid",
  "event_type": "report.completed",
  "event_version": "1.0",
  "service": "report_service",
  "environment": "development",
  "tenant": "dev",
  "timestamp": "2026-05-09T00:00:00.000Z",
  "request_id": "req-uuid",
  "trace_id": "trace-id",
  "correlation_id": "corr-id",
  "user_id": "target-user-id",
  "actor_id": "requester-user-id",
  "aggregate_type": "report",
  "aggregate_id": "report-id",
  "payload": {}
}
```

## S3 / MinIO

Bucket:

```text
microservice
```

Report files:

```text
report_service/<environment>/tenant/<tenant>/users/<target_user_id>/reports/<yyyy>/<MM>/<dd>/<report_id>.<extension>
```

Audit snapshots:

```text
report_service/<environment>/tenant/<tenant>/users/<actor_user_id>/events/<yyyy>/<MM>/<dd>/<HHmmss>_<event_type_slug>_<event_id>.json
```

Generated file metadata includes `checksum_sha256`, `content_type`, `file_size_bytes`, bucket, object key, format, and generated timestamps. Secrets are redacted before writing audit payloads.

## Redis / BullMQ

Redis namespace:

```text
<environment>:report_service:<purpose>:<id>
```

Examples:

```text
development:report_service:report:<report_id>
development:report_service:report:<report_id>:metadata
development:report_service:report:<report_id>:preview
development:report_service:report:<report_id>:progress
development:report_service:bullmq:report-generation
```

Redis is used for BullMQ, metadata cache, preview cache, progress cache, report type cache, access grant cache, idempotency locks, and worker coordination. PostgreSQL remains the source of truth.

## MongoDB logs

Database:

```text
micro_services_logs
```

Collections:

```text
report_service_development_logs
report_service_stage_logs
report_service_production_logs
```

Logs use the canonical document shape with request IDs, trace IDs, correlation IDs, method, path, status, duration, dependency, error code, exception fields, host, and extra metadata. Successful `/hello`, `/health`, and `/docs` request logs are suppressed.

## Swagger /docs

`GET /docs` embeds the OpenAPI document directly into the HTML and uses Swagger UI with:

```text
deepLinking
persistAuthorization
displayRequestDuration
tryItOutEnabled
filter
docExpansion=list
requestInterceptor for X-Request-ID, X-Trace-ID, X-Correlation-ID
```

No public raw OpenAPI route is registered.

## Smoke checks

```bash
curl -i http://localhost:5050/hello
curl -i http://localhost:5050/health
curl -i http://localhost:5050/docs
curl -i http://localhost:5050/openapi.json
curl -i http://localhost:5050/v1/reports/types
```

Expected:

- `/hello` returns 200 pretty JSON.
- `/health` returns 200 or 503 with canonical shape.
- `/docs` returns HTML.
- `/openapi.json` returns 404.
- `/v1/reports/types` without JWT returns 401.

## Swagger and APM implementation notes

The report service `/docs` page follows the same embedded Swagger UI pattern used by the calculator/todo services:

- `GET /docs` is the only public documentation route.
- The OpenAPI document is embedded into the HTML response; there is no public `/openapi.json` or `/v3/api-docs` route.
- Swagger UI uses `swagger-ui-dist@5.19.0`, `StandaloneLayout`, `SwaggerUIStandalonePreset`, same-origin server injection, request duration display, request ID/trace ID/correlation ID injection, and Authorization header normalization.
- The previous local `swagger-ui-dist` rendering path was removed because it triggered `responses_Responses` rendering failures in the browser.

Elastic APM is preloaded before the bundled service entrypoint with `apm-preload.cjs`, then guarded in application startup to avoid double-starting the agent. This lets the Node agent patch HTTP, PostgreSQL, Redis, and other dependencies before the app imports them. The service also records explicit route names, request labels, dependency spans, Kafka consumer transactions, worker transactions, captured errors, host metrics, and ECS-style stdout trace correlation fields so Kibana APM can populate Overview, Transactions, Dependencies, Errors, Metrics, Infrastructure, Service Map, Logs, Alerts, and Dashboards when the Elastic stack and log shippers/agents are running.

## Patch note: malformed JSON request handling

This build fixes a report_service API contract issue where Fastify JSON parser errors were incorrectly returned as HTTP 500 `INTERNAL_ERROR` responses. Malformed JSON requests with `Content-Type: application/json` are now handled as expected client validation failures:

- HTTP status: `400`
- error envelope status: `error`
- error_code: `VALIDATION_ERROR`
- message: `Invalid request body`
- no server stack trace is emitted for expected validation failures

The fix is implemented in `src/http/app.ts` in the global Fastify error handler. It classifies Fastify parser and validation errors such as `FST_ERR_CTP_INVALID_JSON_BODY`, `FST_ERR_VALIDATION`, `FST_ERR_CTP_EMPTY_JSON_BODY`, and `FST_ERR_CTP_INVALID_MEDIA_TYPE` as validation errors instead of internal server errors.

### Verify the fix

```bash
docker rm -f report_service_dev 2>/dev/null || true
docker rmi report_service:dev report_service:latest 2>/dev/null || true

docker build --no-cache -t report_service:dev .
docker run -d --name report_service_dev --env-file .env.dev -p 5050:8080 report_service:dev

curl -i -X POST http://52.66.223.53:5050/v1/reports \
  -H 'Authorization: Bearer <access_token>' \
  -H 'Content-Type: application/json' \
  -d '{"report_type":'
```

Expected result is `HTTP/1.1 400` with the canonical error envelope, not `HTTP/1.1 500`.
