# user_service

Canonical Go / `net/http` implementation of the **user_service** from the unified microservice application contract.

This service owns user profile views and updates, preferences, dashboard aggregation, user activity, local calculator/todo/report projections, cross-user access request creation, visible access grants, and user-created report request records.

The implementation is intentionally service-local. It validates `auth_service` JWTs locally, reads/writes its own PostgreSQL schema, consumes Kafka events into local projection tables, and does not call other application services synchronously.

---

## Contract alignment

| Contract item                    | Implementation                                                                               |
| -------------------------------- | -------------------------------------------------------------------------------------------- |
| Canonical service name           | `user_service`                                                                               |
| Language/runtime                 | Go 1.26 / toolchain Go 1.26.3, `net/http`                                                    |
| Container port                   | `8080` only                                                                                  |
| Public unauthenticated endpoints | `GET /hello`, `GET /health`, `GET /docs`                                                     |
| Protected business base path     | `/v1/users/**`                                                                               |
| JWT validation                   | Local HS256 validation using `USER_JWT_*` values                                             |
| PostgreSQL schema                | `user_service`                                                                               |
| Durable data                     | PostgreSQL domain tables + transactional `outbox_events` and idempotent `kafka_inbox_events` |
| Cache                            | Redis with keys prefixed by `<environment>:user_service:`                                    |
| Events                           | Kafka outbox publisher and Kafka consumer for local projections                              |
| S3                               | MinIO/S3 audit snapshots under canonical key format                                          |
| Structured logs                  | Pretty JSON stdout + MongoDB log collection                                                  |
| Observability                    | Elastic APM HTTP middleware + APM/Elasticsearch health checks                                |
| Documentation                    | Swagger UI at `/docs`; OpenAPI spec is embedded, no public `/openapi.json` route             |
| Infrastructure toggles           | No infrastructure enable/disable gates; only `USER_LOGSTASH_ENABLED=false`                   |

---

## Project layout

```text
user_service/
  .env.dev
  .env.stage
  .env.prod
  .env.example
  Dockerfile
  command.sh
  README.md
  go.mod
  cmd/user-service/main.go
  migrations/
    001_create_user_service_schema.up.sql
    001_create_user_service_schema.down.sql
  internal/
    cache/          Redis cache client
    config/         Canonical USER_* env loading and validation
    docs/           Embedded Swagger/OpenAPI page
    domain/         Canonical domain and event models
    health/         Canonical dependency health contract
    httpapi/        net/http router, envelopes, handlers, CORS, auth middleware
    kafka/          Kafka producer/consumer, outbox publisher, inbox processor
    logging/        Pretty JSON logger with redaction and Mongo sink support
    mongolog/       MongoDB structured log writer and indexes
    persistence/    PostgreSQL repository and projection updates
    platform/       IDs, timestamps, client IP, key helpers
    s3audit/        Canonical S3 audit snapshot writer
    security/       Local auth_service JWT validation
  tests/
    docker_contract_test.go
```

---

## Runtime dependencies

The service expects these infrastructure components at `192.168.56.200` by default:

| Dependency    | Default endpoint             |
| ------------- | ---------------------------- |
| PostgreSQL    | `192.168.56.200:5432`        |
| Redis         | `192.168.56.200:6379`        |
| Kafka         | `192.168.56.200:9092`        |
| MinIO/S3      | `http://192.168.56.200:9000` |
| MongoDB       | `192.168.56.200:27017`       |
| Elastic APM   | `http://192.168.56.200:8200` |
| Elasticsearch | `http://192.168.56.200:9200` |
| Kibana        | `http://192.168.56.200:5601` |

The generated `.env.dev`, `.env.stage`, and `.env.prod` files use the values supplied for that host. The README does not repeat secrets; inspect or rotate the env files directly in your private environment.

---

## Environment files

All env files use the same key order and sections:

```text
.env.dev
.env.stage
.env.prod
.env.example
```

Important canonical values:

```dotenv
USER_SERVICE_NAME=user_service
USER_PORT=8080
USER_POSTGRES_SCHEMA=user_service
USER_KAFKA_EVENTS_TOPIC=user.events
USER_KAFKA_DEAD_LETTER_TOPIC=user_service.dead-letter
USER_S3_BUCKET=microservice
USER_MONGO_DATABASE=mongo_db_micro_services
USER_LOG_FORMAT=pretty-json
USER_LOGSTASH_ENABLED=false
USER_REPORT_ALLOWED_FORMATS=pdf,csv,json,html,xlsx
```

Do not add booleans such as `USER_KAFKA_ENABLED`, `USER_REDIS_ENABLED`, `USER_S3_ENABLED`, `USER_MONGO_ENABLED`, or `USER_SWAGGER_ENABLED`. This build initializes those integrations as part of the application contract.

---

## Build and run

### Docker build

```bash
docker build -t user_service:dev .
```

### Docker run

```bash
docker run --name user_service_dev --env-file .env.dev -p 8080:8080 user_service:dev
```

Only one local container can bind host port `8080` at the same time. When running all six services together, keep each container listening on `8080` internally and map unique host ports or use Compose/Kubernetes service discovery.

### Convenience command

The provided `command.sh` is intentionally fixed, not argument-driven. It removes old containers/images, builds `latest`, then starts dev/stage/prod with unique host ports while keeping the container port at `8080`.

```bash
chmod +x command.sh
./command.sh
```

Host port mapping:

```text
dev   -> localhost:4040 -> container:8080
stage -> localhost:4041 -> container:8080
prod  -> localhost:4042 -> container:8080
```

The script builds `user_service:<env>`, removes any old container with the same canonical name, and runs the container with the matching `.env.<env>` file.

---

## Startup order

On startup the service performs the canonical sequence:

1. Loads `.env.<environment>` when present, while also supporting Docker `--env-file`.
2. Validates every required `USER_*` env key.
3. Configures pretty JSON stdout logging.
4. Configures Elastic APM env values for the Go APM middleware.
5. Connects to PostgreSQL.
6. Applies migrations from `migrations/` into schema `user_service`.
7. Connects to Redis and verifies `PING`.
8. Initializes S3/MinIO and verifies bucket `microservice` exists.
9. Initializes MongoDB structured logging and creates log indexes.
10. Initializes Kafka, creates topics when configured, starts outbox publisher and consumer.
11. Registers `/docs`, `/hello`, `/health`, and protected `/v1/users/**` routes.
12. Starts HTTP server on `0.0.0.0:8080`.
13. Emits `application.started` as pretty JSON.

PostgreSQL, Redis, Kafka, S3, and MongoDB startup failures fail fast. APM and Elasticsearch are reported through `/health`.

---

## Public endpoints

### `GET /hello`

No dependency checks. Returns canonical service identity:

```json
{
  "status": "ok",
  "message": "user_service is running",
  "service": {
    "name": "user_service",
    "env": "development",
    "version": "v1.0.0"
  }
}
```

### `GET /health`

Checks the canonical dependency keys:

```text
jwt, postgres, redis, kafka, s3, mongodb, apm, elasticsearch
```

If any dependency is unavailable, the response status is `down` and HTTP status is `503`. Secrets, host credentials, JWTs, access keys, and passwords are never included.

### `GET /docs`

Serves Swagger UI with an embedded OpenAPI document and `bearerAuth` security scheme. There is no public `/openapi.json` route.

---

## Authentication and authorization

Every `/v1/users/**` route requires a Bearer JWT issued by `auth_service`.

Required JWT behavior:

- Algorithm: `HS256`
- Issuer: `auth`
- Audience: `micro-app`
- Tenant must match `USER_TENANT` when `USER_SECURITY_REQUIRE_TENANT_MATCH=true`
- Allowed roles: `user`, `admin`, `service`, `system`
- Allowed admin statuses: `not_requested`, `pending`, `approved`, `rejected`, `suspended`

Cross-user reads are allowed when one of these is true:

1. Caller is reading their own data.
2. Caller has `role=admin` and `admin_status=approved`.
3. Caller has `role=service` or `role=system`.
4. Caller has an active, unexpired grant in `user_access_grants` matching the resource and scope.

Missing, invalid, expired, or tenant-mismatched JWTs return `401`. Valid JWTs without permission return `403`.

---

## API catalog

All responses use the canonical success/error envelopes.

| Method  | Path                                                    | Purpose                            |
| ------- | ------------------------------------------------------- | ---------------------------------- |
| `GET`   | `/v1/users/me`                                          | Current profile                    |
| `PATCH` | `/v1/users/me`                                          | Update current profile             |
| `GET`   | `/v1/users/me/preferences`                              | Current preferences                |
| `PUT`   | `/v1/users/me/preferences`                              | Replace preferences                |
| `GET`   | `/v1/users/me/activity`                                 | Current user activity              |
| `GET`   | `/v1/users/me/dashboard`                                | Current user dashboard             |
| `GET`   | `/v1/users/me/calculations`                             | Own calculation projections        |
| `GET`   | `/v1/users/me/calculations/{calculationId}`             | Own calculation detail             |
| `GET`   | `/v1/users/{targetUserId}/calculations`                 | Cross-user calculation projections |
| `GET`   | `/v1/users/{targetUserId}/calculations/{calculationId}` | Cross-user calculation detail      |
| `GET`   | `/v1/users/me/todos`                                    | Own todo projections               |
| `GET`   | `/v1/users/me/todos/summary`                            | Own todo summary                   |
| `GET`   | `/v1/users/me/todos/activity`                           | Own todo activity                  |
| `GET`   | `/v1/users/me/todos/{todoId}`                           | Own todo detail                    |
| `GET`   | `/v1/users/{targetUserId}/todos`                        | Cross-user todo projections        |
| `GET`   | `/v1/users/{targetUserId}/todos/summary`                | Cross-user todo summary            |
| `GET`   | `/v1/users/{targetUserId}/todos/activity`               | Cross-user todo activity           |
| `GET`   | `/v1/users/{targetUserId}/todos/{todoId}`               | Cross-user todo detail             |
| `POST`  | `/v1/users/access-requests`                             | Request cross-user access          |
| `GET`   | `/v1/users/access-requests`                             | List caller access requests        |
| `GET`   | `/v1/users/access-requests/{requestId}`                 | Get caller access request          |
| `POST`  | `/v1/users/access-requests/{requestId}/cancel`          | Cancel caller access request       |
| `GET`   | `/v1/users/access-grants`                               | List grants visible to caller      |
| `GET`   | `/v1/users/reports/types`                               | List local report types            |
| `POST`  | `/v1/users/me/reports`                                  | Create own report request          |
| `GET`   | `/v1/users/me/reports`                                  | List own report requests           |
| `GET`   | `/v1/users/me/reports/{reportId}`                       | Get own report request             |
| `POST`  | `/v1/users/me/reports/{reportId}/cancel`                | Cancel own report request          |
| `POST`  | `/v1/users/{targetUserId}/reports`                      | Request report for another user    |
| `GET`   | `/v1/users/{targetUserId}/reports`                      | List cross-user report requests    |
| `GET`   | `/v1/users/{targetUserId}/reports/{reportId}`           | Get cross-user report request      |
| `POST`  | `/v1/users/{targetUserId}/reports/{reportId}/cancel`    | Cancel cross-user report request   |

---

## Example requests

### Update profile

```bash
curl -X PATCH http://localhost:8080/v1/users/me \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{
    "full_name": "Md Jakir Hosen",
    "timezone": "Asia/Dhaka",
    "locale": "en",
    "metadata": {"source": "profile-page"}
  }'
```

### Replace preferences

```bash
curl -X PUT http://localhost:8080/v1/users/me/preferences \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{
    "timezone": "Asia/Dhaka",
    "locale": "en",
    "theme": "dark",
    "notifications_enabled": true
  }'
```

### Create access request

```bash
curl -X POST http://localhost:8080/v1/users/access-requests \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{
    "target_user_id": "other-user-uuid",
    "resource_type": "calculator",
    "scope": "calculator:history:read",
    "reason": "Need to review calculation history for support investigation.",
    "expires_at": "2026-06-07T00:00:00Z"
  }'
```

### Create report request

```bash
curl -X POST http://localhost:8080/v1/users/me/reports \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{
    "report_type": "calculator_history_report",
    "format": "pdf",
    "date_from": "2026-05-01",
    "date_to": "2026-05-09",
    "filters": {},
    "options": {}
  }'
```

---

## PostgreSQL schema

The migration creates this service-local schema:

```text
schema user_service
  user_profiles
  user_preferences
  user_activity_events
  user_calculation_projections
  user_todo_projections
  user_access_requests
  user_access_grants
  user_report_requests
  user_report_projections
  user_service_state
  outbox_events
  kafka_inbox_events
```

`outbox_events` and `kafka_inbox_events` follow the canonical DDL, including status constraints and idempotency indexes. There are no cross-service foreign keys; all cross-service data arrives through Kafka projections.

---

## Kafka behavior

### Produced topics

| Topic                      | Events                                                                                               |
| -------------------------- | ---------------------------------------------------------------------------------------------------- |
| `user.events`              | `user.profile.updated`, `user.preferences.updated`, `user.report.requested`, `user.report.cancelled` |
| `access.events`            | `access.requested`, `access.request.cancelled`                                                       |
| `user_service.dead-letter` | Failed publish payloads                                                                              |

### Consumed topics

```text
auth.events, auth.admin.requests, auth.admin.decisions, admin.events,
user.events, calculator.events, todo.events, report.events, access.events
```

### Event envelope

Every published event uses:

```json
{
  "event_id": "evt-uuid",
  "event_type": "user.profile.updated",
  "event_version": "1.0",
  "service": "user_service",
  "environment": "development",
  "tenant": "dev",
  "timestamp": "2026-05-09T00:00:00Z",
  "request_id": "req-uuid",
  "trace_id": "trace-id",
  "correlation_id": "corr-id",
  "user_id": "resource-owner-user-id",
  "actor_id": "caller-user-id",
  "aggregate_type": "user_profile",
  "aggregate_id": "resource-id",
  "payload": {}
}
```

Kafka message headers include `event_id`, `event_type`, `service`, `tenant`, `trace_id`, and `correlation_id`.

---

## Redis cache keys

All keys begin with:

```text
<environment>:user_service:
```

Examples:

```text
development:user_service:profile:dev:<user_id>
development:user_service:preferences:dev:<user_id>
development:user_service:dashboard:dev:<user_id>
development:user_service:calculations:dev:<user_id>:50:0
```

Mutations invalidate affected cache prefixes after the PostgreSQL transaction commits.

---

## S3 audit snapshots

Mutation endpoints write pretty JSON audit snapshots to:

```text
s3://microservice/user_service/<environment>/tenant/<tenant>/users/<actor_user_id>/events/<yyyy>/<MM>/<dd>/<HHmmss>_<event_type_slug>_<event_id>.json
```

The audit payload follows the canonical body and excludes passwords, JWTs, refresh tokens, access keys, secret keys, authorization headers, and connection secrets.

---

## MongoDB structured logs

Logs are written to:

```text
database:   db_micro_services
collection: user_service_<environment>_logs
```

The log writer creates indexes for timestamp, level, event, request ID, trace ID, user ID, path/status, and error code. Non-production also creates a 14-day TTL index.

Successful `/hello`, `/health`, and `/docs` requests are suppressed. Warnings, errors, auth failures, authorization denials, infrastructure failures, Kafka failures, S3 failures, startup, shutdown, and migrations are logged.

---

## Local checks

Run formatting:

```bash
gofmt -w $(find . -name '*.go')
```

Run unit tests:

```bash
go test ./...
```

The sandbox used to generate this code only has Go 1.23.2 and no external network, so it cannot download the Go 1.26.3 toolchain or module checksums. In a normal development environment, `go mod tidy`, `go test ./...`, and Docker builds will use Go 1.26.3 and download dependencies from the Go module proxy.

---

## Smoke test

After the container starts:

```bash
curl -i http://localhost:4040/hello
curl -i http://localhost:4040/health
curl -i http://localhost:4040/docs
curl -i http://localhost:4040/live
curl -i http://localhost:4040/v1/users/me

curl -i http://localhost:4041/hello
curl -i http://localhost:4041/health
curl -i http://localhost:4041/docs

curl -i http://localhost:4042/hello
curl -i http://localhost:4042/health
curl -i http://localhost:4042/docs
```

Expected behavior:

- `/hello` returns `200`.
- `/health` returns `200` when dependencies are up, otherwise `503` with dependency error codes.
- `/docs` returns Swagger UI.
- `/live` returns `404`.
- `/v1/users/me` without JWT returns `401`.

---

## Security notes

- Do not commit real production secrets to a public repository.
- Rotate any secret after sharing artifacts outside your trusted environment.
- The service redacts secret-looking keys before stdout/Mongo logging.
- JWTs and authorization headers are not logged or stored in S3 audit objects.
- Cross-user reads require same-user, approved admin, service/system role, or active grant authorization.

---

## Troubleshooting

### Docker build error: missing `go.sum` entries

The previous failure happened because the archive had no usable `go.sum` and Docker reached `go build` before all dependency checksums were materialized. This rebuild fixes the Docker build path by copying `go.mod` first, downloading modules, removing any stale or empty `go.sum` copied from the archive, running `go mod tidy`, and then building with `go build -mod=mod` using Go 1.26.3.

```bash
docker build -t user_service:dev .
docker rm -f user_service_dev 2>/dev/null || true
docker run --name user_service_dev --env-file .env.dev -p 4040:8080 user_service:dev
```

For local host builds outside Docker, run module resolution once before tests/builds:

```bash
go mod tidy
go test ./...
```

### Startup fails at PostgreSQL

Verify host, port, credentials, database name, and that the configured user can create schema objects and the `pgcrypto` extension.

### Startup fails at S3

Verify the MinIO endpoint and that bucket `microservice` already exists. This service checks bucket existence and does not silently switch to local files.

### `/health` reports APM down

Verify `USER_APM_SERVER_URL` and `USER_APM_SECRET_TOKEN`. The application may still start, but `/health` is down until APM is reachable.

### `/health` reports Elasticsearch down

Verify `USER_ELASTICSEARCH_URL`, `USER_ELASTICSEARCH_USERNAME`, and `USER_ELASTICSEARCH_PASSWORD`.

### Protected routes return `401`

Check JWT signature, issuer, audience, algorithm, expiration, `tenant`, and required claims.

### Cross-user routes return `403`

Create an access request through user_service and approve it in admin_service so an active grant is projected into `user_access_grants` through Kafka.

---

## Swagger/API test coverage helper

This rebuild includes a service-specific smoke/contract script:

```bash
chmod +x user_service_api_full_smoke_test.sh
./user_service_api_full_smoke_test.sh \
  --user-host 192.168.56.100 --user-port 4040 \
  --auth-host 192.168.56.100 --auth-port 6060 \
  --verbose
```

URL form:

```bash
./user_service_api_full_smoke_test.sh \
  --user-url http://192.168.56.100:4040 \
  --auth-url http://192.168.56.100:6060
```

The script intentionally tests both valid and invalid requests:

- public `/hello`, `/health`, `/docs`
- rejected public routes `/`, `/live`, `/ready`, `/healthy`
- missing token and invalid token `401`
- wrong method `405`
- invalid query strings such as `limit=abc`, `limit=0`, `limit=101`, `offset=abc`, `offset=-1`
- malformed JSON request bodies
- missing required request body fields
- unsupported report format
- normal profile, preferences, dashboard, activity, security/RBAC views
- own calculation/todo/report projection reads
- cross-user `403` checks without an access grant
- access request create/read/cancel/conflict flow
- report request create/read/metadata/progress/cancel/conflict flow
- canonical success and error response envelope shape

Current Swagger operation inventory:

| Category | Count |
|---|---:|
| Total OpenAPI paths | 37 |
| Total operations/APIs | 42 |
| Public unauthenticated operations | 3 |
| Protected `/v1/users/**` operations | 39 |
| Operations with JSON request bodies | 5 |
| Documented response status codes | 10 |

Documented response status codes:

```text
200, 201, 400, 401, 403, 404, 405, 409, 500, 503
```

Operations with request bodies:

```text
PATCH /v1/users/me
PUT   /v1/users/me/preferences
POST  /v1/users/access-requests
POST  /v1/users/me/reports
POST  /v1/users/{targetUserId}/reports
```

## Kibana APM Dependencies

The Kibana APM **Dependencies** tab is populated from Elastic APM dependency/exit spans. It is not populated by the `/health` JSON body alone.

This build instruments dependency calls for:

- PostgreSQL
- Redis
- Kafka
- S3 / MinIO
- MongoDB
- APM server health HTTP call
- Elasticsearch health HTTP call

After deploying a new image, generate dependency traffic:

```bash
./user_service_apm_dependency_probe.sh --host 192.168.56.100 --port 4040 --count 20
```

Then open Kibana APM, go to `user_service > Dependencies`, set the time range to **Last 15 minutes**, and click **Refresh**. It can take a short ingestion delay before the dependency rows appear.

