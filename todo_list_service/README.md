# todo_list_service

`todo_list_service` is the canonical Todo microservice for the unified six-service application. It owns authenticated todo CRUD, status transitions, todo history, soft delete, approved-admin/service hard delete, transactional Kafka outbox publishing, Kafka inbox idempotency for local projections, Redis caching, S3/MinIO audit snapshots, MongoDB structured logs, Elastic APM traces, Elasticsearch health, and an embedded interactive API console at `/docs`.

The service follows the uploaded application contract and mirrors the working Auth/Admin/Calculator integration style while keeping the Java package name `com.microservice.todo` to avoid unnecessary churn.

## Tooling

| Area                      | Version / target         |
| ------------------------- | ------------------------ |
| Java                      | JDK 25 toolchain         |
| Gradle wrapper            | 9.5.0                    |
| Spring Boot Gradle plugin | 4.0.6                    |
| Container port            | 8080                     |
| Runtime image             | `eclipse-temurin:25-jre` |
| Build image               | `gradle:9.5.0-jdk25`     |

## Public route contract

Only these unauthenticated public routes are implemented:

| Method | Path      | Purpose                                                                                             |
| ------ | --------- | --------------------------------------------------------------------------------------------------- |
| GET    | `/hello`  | Service identity only. No dependency checks.                                                        |
| GET    | `/health` | Canonical dependency health for JWT, PostgreSQL, Redis, Kafka, S3, MongoDB, APM, and Elasticsearch. |
| GET    | `/docs`   | Embedded interactive Swagger UI with OpenAPI spec in the HTML page.                                 |

These routes must not be public API routes and should return `404` when called directly:

```text
/
/live
/ready
/healthy
/openapi.json
/v3/api-docs
/v3/api-docs/**
/swagger-ui/**
/swagger-ui.html
/actuator
/actuator/**
```

## Protected business APIs

All business APIs are under `/v1/todos` and require a valid Auth service JWT signed with `TODO_JWT_SECRET`.

| Method | Path                      | Behavior                                                                                                                                                           |
| ------ | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| POST   | `/v1/todos`               | Create todo owned by JWT `sub`. Defaults: `status=PENDING`, `priority=MEDIUM`.                                                                                     |
| GET    | `/v1/todos`               | List/search/filter caller todos. Supports `status`, `priority`, `tag`, `search`, `archived`, `due_after`, `due_before`, `include_deleted`, `page`, `size`, `sort`. |
| GET    | `/v1/todos/overdue`       | List active, non-deleted todos due before now.                                                                                                                     |
| GET    | `/v1/todos/today`         | List todos due today in UTC.                                                                                                                                       |
| GET    | `/v1/todos/{id}`          | Read todo by id. Allows owner, approved admin, service/system, or local access grant.                                                                              |
| PUT    | `/v1/todos/{id}`          | Update title, description, priority, due date, tags. Does not change status.                                                                                       |
| PATCH  | `/v1/todos/{id}/status`   | Apply valid status transition. Invalid transitions return `409 TODO_INVALID_STATUS_TRANSITION`.                                                                    |
| POST   | `/v1/todos/{id}/complete` | Transition to `COMPLETED` and set `completed_at`.                                                                                                                  |
| POST   | `/v1/todos/{id}/archive`  | Transition to `ARCHIVED`, set `archived=true`, set `archived_at`.                                                                                                  |
| POST   | `/v1/todos/{id}/restore`  | Restore archived or soft-deleted todo.                                                                                                                             |
| GET    | `/v1/todos/{id}/history`  | Return todo history. Allows owner, approved admin, service/system, or local grant.                                                                                 |
| DELETE | `/v1/todos/{id}`          | Soft delete by setting `deleted_at`. Emits `todo.deleted`.                                                                                                         |
| DELETE | `/v1/todos/{id}/hard`     | Hard delete. Only approved admin, service, or system role.                                                                                                         |

## JWT validation

Todo validates JWTs locally. It does not call Auth synchronously.

Required claims:

```json
{
  "iss": "auth",
  "aud": "micro-app",
  "sub": "user-uuid",
  "jti": "token-id",
  "username": "jakir",
  "email": "jakir@example.com",
  "role": "user",
  "admin_status": "not_requested",
  "tenant": "dev",
  "iat": 1710000000,
  "nbf": 1710000000,
  "exp": 1710000900
}
```

Roles: `user`, `admin`, `service`, `system`.

Admin statuses: `not_requested`, `pending`, `approved`, `rejected`, `suspended`.

Error behavior:

| Case                    | HTTP | Error code        |
| ----------------------- | ---: | ----------------- |
| Missing token           |  401 | `UNAUTHORIZED`    |
| Invalid/expired token   |  401 | `UNAUTHORIZED`    |
| Tenant mismatch         |  403 | `TENANT_MISMATCH` |
| Insufficient permission |  403 | `TODO_FORBIDDEN`  |

## Todo domain rules

Statuses:

```text
PENDING | IN_PROGRESS | COMPLETED | CANCELLED | ARCHIVED
```

Priorities:

```text
LOW | MEDIUM | HIGH | URGENT
```

Allowed transitions:

```text
PENDING     -> IN_PROGRESS | COMPLETED | CANCELLED | ARCHIVED
IN_PROGRESS -> COMPLETED | CANCELLED | ARCHIVED
COMPLETED   -> ARCHIVED
CANCELLED   -> ARCHIVED
ARCHIVED    -> PENDING through restore
```

## Infrastructure implementation

### PostgreSQL

Schema: `todo`.

Tables:

```text
todo.todos
todo.todo_history
todo.outbox_events
todo.kafka_inbox_events
todo.access_grant_projections
```

`todo_history.changes` and `todo_history.payload` are `jsonb` fields. The outbox and inbox DDL follows the canonical schema. No cross-service foreign keys are created. The only foreign key is service-owned: `todo_history.todo_id -> todo.todos(id)`.

### Redis

Redis is a cache/coordination dependency. PostgreSQL remains the source of truth. All keys use:

```text
<environment>:todo_list_service:<purpose>:<id>
```

Implemented key families:

```text
development:todo_list_service:record:<tenant>:<todo_id>
development:todo_list_service:list:<tenant>:<user_id>:<hash>
development:todo_list_service:today:<tenant>:<user_id>:<limit>
development:todo_list_service:overdue:<tenant>:<user_id>:<limit>
development:todo_list_service:history:<tenant>:<todo_id>
```

Every cache write has TTL from `TODO_REDIS_CACHE_TTL_SECONDS`. Mutations invalidate record, list, today, overdue, and history caches.

### Kafka

Todo publishes to:

```text
todo.events
```

Dead letter topic:

```text
todo.dead-letter
```

Todo consumes from:

```text
auth.events,auth.admin.requests,auth.admin.decisions,admin.events,user.events,calculator.events,todo.events,report.events,access.events
```

Outgoing event types:

```text
todo.created
todo.updated
todo.status_changed
todo.completed
todo.archived
todo.restored
todo.deleted
todo.hard_deleted
todo.audit.s3_written
todo.audit.s3_failed
```

Kafka publishing is done through `todo.outbox_events`. The HTTP transaction writes the todo mutation, history row, and outbox rows before commit. The scheduled outbox publisher sends pending events and marks them `SENT`, `FAILED`, or `DEAD_LETTERED`.

Incoming events are first inserted into `todo.kafka_inbox_events` for idempotency. Duplicate `event_id` values are ignored. Access grant events update `todo.access_grant_projections`.

### S3 / MinIO audit snapshots

Bucket:

```text
microservice
```

Path format:

```text
todo_list_service/<environment>/tenant/<tenant>/users/<actor_user_id>/events/<yyyy>/<MM>/<dd>/<HHmmss>_<event_type_slug>_<event_id>.json
```

Audit body includes canonical fields: event id/type, service, environment, tenant, user/actor, aggregate, request/trace/correlation ids, client IP, user agent, timestamp, and safe redacted payload. It never stores JWTs, Authorization headers, passwords, access keys, secret keys, or connection strings.

### MongoDB structured logs

Database:

```text
db_micro_services
```

Collections:

```text
todo_list_service_development_logs
todo_list_service_stage_logs
todo_list_service_production_logs
```

Indexes are created for timestamp, level, event, request id, trace id, user id, path/status, and error code. Log payloads are redacted through `SecretRedactor`.

### Elastic APM / Elasticsearch

APM is attached from `TODO_APM_SERVER_URL`, `TODO_APM_SECRET_TOKEN`, `TODO_APM_TRANSACTION_SAMPLE_RATE`, and `TODO_APM_CAPTURE_BODY`. Service name is `todo_list_service`. Environment comes from `TODO_ENV`.

`/health` checks Elasticsearch via `TODO_ELASTICSEARCH_URL` and reports the canonical `elasticsearch` dependency key.

## Environment files

Required files:

```text
.env.dev
.env.stage
.env.prod
.env.example
```

All four files have identical keys in identical order. `.env.example` is sanitized. The runtime env files should be treated as sensitive because they contain connection credentials.

Forbidden infrastructure toggles are rejected at startup, including:

```text
TODO_S3_ENABLED
TODO_KAFKA_ENABLED
TODO_REDIS_ENABLED
TODO_POSTGRES_ENABLED
TODO_MONGO_ENABLED
TODO_APM_ENABLED
TODO_SWAGGER_ENABLED
TODO_S3_REQUIRED
TODO_KAFKA_REQUIRED
TODO_REDIS_REQUIRED
TODO_POSTGRES_REQUIRED
TODO_MONGO_REQUIRED
TODO_MONGO_LOGS_ENABLED
TODO_APM_REQUIRED
TODO_ELASTICSEARCH_REQUIRED
```

The only explicit disabled integration toggle is:

```text
TODO_LOGSTASH_ENABLED=false
```

## Build

```bash
./gradlew clean test
./gradlew clean bootJar
```

Docker build:

```bash
docker build -t todo_list_service:dev .
```

## Run one container

```bash
docker run --name todo_list_service_dev --env-file .env.dev -p 3030:8080 todo_list_service:dev
```

Container port remains `8080`; host ports `3030`, `3031`, and `3032` are used by `command.sh` for local multi-service testing.

## Run dev, stage, and prod local containers

```bash
chmod +x command.sh
./command.sh
```

The script builds `latest`, `dev`, `stage`, and `prod`, then runs:

```text
todo_list_service_dev   -> 3030:8080
todo_list_service_stage -> 3031:8080
todo_list_service_prod  -> 3032:8080
```

## Smoke checks

```bash
curl -i http://localhost:3030/hello
curl -i http://localhost:3030/health
curl -i http://localhost:3030/docs

curl -i http://localhost:3030/
curl -i http://localhost:3030/live
curl -i http://localhost:3030/ready
curl -i http://localhost:3030/healthy
curl -i http://localhost:3030/openapi.json
curl -i http://localhost:3030/v3/api-docs
curl -i http://localhost:3030/swagger-ui/index.html
curl -i http://localhost:3030/actuator/health
```

Expected: first three routes work; rejected routes return 404.

## Static contract test

```bash
python3 tests/contract_checks.py
```

This validates env key order, forbidden toggles, Java/Spring/Gradle target versions, Dockerfile, command.sh, public route/security contract, health shape, docs embedding, migration DDL, Kafka event envelope, S3 key format, Redis namespace, and Mongo log shape.

## Full integration flow

1. Start PostgreSQL, Redis, Kafka, MinIO/S3, MongoDB, Elastic APM, Elasticsearch, and Kibana.
2. Start Auth service.
3. Start Admin service.
4. Start Calculator service.
5. Start Todo service.
6. Login through Auth service and copy the access token.
7. Open Todo `/docs`, authorize with `Bearer <access_token>`, and create a todo.
8. Verify rows in `todo.todos`, `todo.todo_history`, and `todo.outbox_events`.
9. Verify `todo.events` receives emitted events.
10. Verify S3 audit snapshot object exists.
11. Verify Redis cache keys are populated/invalidated.
12. Verify MongoDB structured logs and APM traces.
13. Verify normal user cannot hard-delete and approved admin/service/system can.

## Notes

- Todo does not issue JWTs, hash passwords, or synchronously call Auth/Admin/Calculator/User/Report.
- Cross-service state is consumed through Kafka and stored in local projections.
- The OpenAPI document is embedded in `/docs`; generated OpenAPI JSON files are not committed or publicly exposed.
