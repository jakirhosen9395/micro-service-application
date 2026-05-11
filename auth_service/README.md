# auth_service

`auth_service` is the canonical FastAPI authentication service for the unified microservice application. It owns user signup, signin/login, JWT issuing, refresh token rotation, logout/session revocation, password forgot/reset/change flows, current-user lookup, JWT/session verification, admin registration requests, admin approval/rejection state, default admin bootstrap, auth audit events, Kafka auth events, S3 audit snapshots, MongoDB structured logs, Redis session/token helpers, PostgreSQL schema ownership, and the interactive `/docs` API console.

The service listens inside the container on port `8080` and exposes only three unauthenticated public system routes:

```text
GET /hello
GET /health
GET /docs
```

All business APIs live under `/v1/**`. Protected APIs require a valid `auth_service` JWT. Approved-admin APIs additionally require `role=admin`, `admin_status=approved`, `status=active`, and tenant match.

---

## What is fixed in this rebuild

This rebuild consolidates all previous fixes and hardens the service for real runtime use:

- Swagger CORS/host-port issue fixed by using same-origin OpenAPI server `/`.
- `/docs` rebuilt as an API console with workflow guidance, persistent authorization, examples, request tracing headers, and bearer JWT support.
- `/openapi.json`, `/`, `/live`, `/ready`, and `/healthy` remain unavailable and return `404`.
- `/v1/signup` supports normal user signup and admin signup request using `account_type=admin` plus `reason`.
- `/v1/admin/register` remains the canonical public admin-registration request endpoint.
- Password reset accepts both `reset_token` and `token` request fields.
- Password reset clearly separates `request_id` from `reset_token`; `request_id` is only tracing metadata.
- Audit/outbox/inbox JSON serialization handles `date` and `datetime` safely.
- Kafka topic creation no longer depends on old `kafka-python`; it uses `aiokafka` admin APIs.
- Docker build uses Python 3.14 stable and cache-friendly layered dependency installation.
- `aiokafka` is upgraded to a Python 3.14-compatible release.
- Generated cache files are removed from the source package.
- Only one markdown document exists: this `README.md`.
- Environment files retain identical key order.
- Elastic APM middleware and instrumentation are initialized for HTTP transactions, errors, and dependency spans.

---

## Runtime stack

The rebuild pins stable production versions suitable for the requested May 2026 target:

```text
Python:        3.14 stable Docker line
FastAPI:       0.136.1
Pydantic:      2.13.4
Uvicorn:       0.41.0
asyncpg:       0.31.0
redis-py:      7.4.0
aiokafka:      0.14.0
boto3:         1.42.58
motor/pymongo: 3.7.1 / 4.15.4
elastic-apm:   6.25.0
elasticsearch: 8.19.3 client line
Alembic:       1.17.2
Argon2:        argon2-cffi 25.1.0
PyJWT:         2.10.1
pytest:        9.0.2
ruff:          0.13.2
```

Python 3.14.4 is the latest stable Python 3.14 maintenance release available in the reviewed release stream; release candidates are intentionally avoided for production.

---

## Repository layout

```text
auth_service/
  app/
    config/
    domain/
    health/
    http/
      routes/
    kafka/
    logging/
    observability/
    persistence/
    redis/
    s3/
    security/
    services/
    utils/
    main.py
    preflight.py
  migrations/
    env.py
    001_auth_schema.sql
    versions/001_initial_auth_schema.py
  scripts/validate_env_contract.py
  tests/
  .env.dev
  .env.stage
  .env.prod
  .env.example
  .dockerignore
  Dockerfile
  command.sh
  requirements.txt
  pyproject.toml
  alembic.ini
  README.md
```

No generated `__pycache__`, `.pytest_cache`, `*.pyc`, OpenAPI JSON file, generated Swagger assets, or extra markdown files are shipped.

---

## Infrastructure

The env files point to the shared VM host:

```text
192.168.56.200
```

Required dependencies:

```text
PostgreSQL:     192.168.56.200:5432
Redis:          192.168.56.200:6379
Kafka:          192.168.56.200:9092
MinIO/S3:       http://192.168.56.200:9000
MongoDB:        192.168.56.200:27017
Elastic APM:    http://192.168.56.200:8200
Elasticsearch:  http://192.168.56.200:9200
Kibana:         http://192.168.56.200:5601
```

The real credentials are stored in the `.env.*` files. Do not paste credentials, JWTs, access tokens, refresh tokens, authorization headers, access keys, secret keys, or database passwords into logs, Kafka messages, S3 audit payloads, screenshots, tickets, or documentation examples.

---

## Environment contract

The service includes:

```text
.env.dev
.env.stage
.env.prod
.env.example
```

All four files have the same keys in the same order. Only values differ.

Validate this contract:

```bash
python -m scripts.validate_env_contract
```

Forbidden infrastructure boolean gates are rejected at config load time, including:

```text
AUTH_S3_ENABLED
AUTH_KAFKA_ENABLED
AUTH_REDIS_ENABLED
AUTH_POSTGRES_ENABLED
AUTH_MONGO_ENABLED
AUTH_MONGO_LOGS_ENABLED
AUTH_APM_ENABLED
AUTH_SWAGGER_ENABLED
AUTH_POSTGRES_REQUIRED
AUTH_REDIS_REQUIRED
AUTH_KAFKA_REQUIRED
AUTH_S3_REQUIRED
AUTH_MONGO_REQUIRED
AUTH_ELASTICSEARCH_REQUIRED
AUTH_APM_REQUIRED
```

Only this explicit integration flag is allowed:

```dotenv
AUTH_LOGSTASH_ENABLED=false
```

---

## Build and run

Make the script executable:

```bash
chmod +x command.sh
```

Run the exact requested script:

```bash
./command.sh
```

The script builds `latest`, `dev`, `stage`, and `prod` images and starts containers with these host ports:

```text
dev:   6060 -> 8080
stage: 6061 -> 8080
prod:  6061 -> 8080
```

`stage` and `prod` both bind host port `6061`, so they cannot run at the same time on the same machine unless one is stopped or the script is edited later.

Manual dev build/run:

```bash
docker build -t auth_service:dev .
docker rm -f auth_service_dev 2>/dev/null || true
docker run -d --name auth_service_dev --env-file .env.dev -p 6060:8080 auth_service:dev
```

Smoke test:

```bash
curl -i http://192.168.56.100:6060/hello
curl -i http://192.168.56.100:6060/health
curl -i http://192.168.56.100:6060/docs
curl -i http://192.168.56.100:6060/openapi.json
```

Expected: `/hello`, `/health`, and `/docs` are available; `/openapi.json` is `404`.

---

## Startup sequence

At startup, the service:

1. Loads `.env.<environment>` from the service root.
2. Validates all required env keys and forbidden gates.
3. Configures pretty JSON stdout logging and MongoDB log writer.
4. Initializes Elastic APM instrumentation.
5. Registers request context middleware for request ID, trace ID, correlation ID, tenant, and user context.
6. Connects to PostgreSQL.
7. Applies the auth schema migration when `AUTH_POSTGRES_MIGRATION_MODE=auto`.
8. Connects to Redis and verifies `PING`.
9. Connects Kafka producer/consumer and creates topics best-effort.
10. Connects S3/MinIO and verifies bucket access.
11. Connects MongoDB and creates structured log indexes.
12. Connects Elasticsearch.
13. Registers `/hello`, `/health`, `/docs`, and protected `/v1/**` routes.
14. Bootstraps the default approved admin.
15. Starts HTTP server on `0.0.0.0:8080`.
16. Emits `application.started` in pretty JSON.

Required dependency failures fail startup or cause `/health` to return `503`.

---

## API catalog

### Public system routes

| Method | Path      | Auth | Purpose                                                                             |
| ------ | --------- | ---: | ----------------------------------------------------------------------------------- |
| GET    | `/hello`  |   No | Service identity check only.                                                        |
| GET    | `/health` |   No | Dependency health for JWT, Postgres, Redis, Kafka, S3, MongoDB, APM, Elasticsearch. |
| GET    | `/docs`   |   No | Interactive guided API console with embedded OpenAPI spec.                          |

Rejected routes:

```text
GET /
GET /live
GET /ready
GET /healthy
GET /openapi.json
```

### Auth routes

| Method | Path                                    |           Auth | Purpose                                                                            |
| ------ | --------------------------------------- | -------------: | ---------------------------------------------------------------------------------- |
| POST   | `/v1/signup`                            |             No | Create normal user and session, or admin signup request with `account_type=admin`. |
| POST   | `/v1/signin`                            |             No | Preferred signin endpoint.                                                         |
| POST   | `/v1/login`                             |             No | Compatibility alias for signin.                                                    |
| POST   | `/v1/logout`                            |            Yes | Revoke current session and blacklist current JWT `jti`.                            |
| POST   | `/v1/token/refresh`                     |             No | Rotate refresh token and issue a new access token.                                 |
| GET    | `/v1/me`                                |            Yes | Get current safe user profile.                                                     |
| GET    | `/v1/verify`                            |            Yes | Verify JWT claims and active session.                                              |
| POST   | `/v1/password/forgot`                   |             No | Start password reset flow.                                                         |
| POST   | `/v1/password/reset`                    |             No | Reset password using reset token.                                                  |
| POST   | `/v1/password/change`                   |            Yes | Change password for authenticated user.                                            |
| POST   | `/v1/admin/register`                    |             No | Request admin account registration.                                                |
| GET    | `/v1/admin/requests`                    | Approved admin | List admin registration requests.                                                  |
| POST   | `/v1/admin/requests/{user_id}/decision` | Approved admin | Approve/reject admin request.                                                      |

---

## Signup examples

Normal signup:

```bash
curl -X POST 'http://192.168.56.100:6060/v1/signup' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "username": "jakir",
    "email": "jakir@example.com",
    "password": "Secret123!",
    "full_name": "Md Jakir Hosen",
    "birthdate": "1998-05-20",
    "gender": "male"
  }'
```

Admin signup request through `/v1/signup`:

```bash
curl -X POST 'http://192.168.56.100:6060/v1/signup' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "username": "admin-jakir",
    "email": "admin.jakir@example.com",
    "password": "Secret123!",
    "full_name": "Md Jakir Hosen",
    "birthdate": "1998-05-20",
    "gender": "male",
    "account_type": "admin",
    "reason": "I need admin access to manage users and review operational issues."
  }'
```

Canonical admin registration endpoint:

```bash
curl -X POST 'http://192.168.56.100:6060/v1/admin/register' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "username": "admin-jakir-2",
    "email": "admin.jakir2@example.com",
    "password": "Secret123!",
    "full_name": "Md Jakir Hosen",
    "birthdate": "1998-05-20",
    "gender": "male",
    "reason": "I need admin access to manage users and review operational issues."
  }'
```

Admin accounts are created as `role=admin` and `admin_status=pending`. They are not approved admins until an existing approved admin approves them.

---

## Signin and bearer token use

Signin:

```bash
curl -X POST 'http://192.168.56.100:6060/v1/signin' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "username_or_email": "jakir",
    "password": "Secret123!"
  }'
```

Use the access token:

```bash
ACCESS_TOKEN='<copy data.tokens.access_token>'

curl -i 'http://192.168.56.100:6060/v1/me' \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

Protected routes return:

```text
missing token        -> 401 UNAUTHORIZED
expired token        -> 401 TOKEN_EXPIRED
invalid token        -> 401 INVALID_TOKEN
revoked token        -> 401 TOKEN_REVOKED
tenant mismatch      -> 403 TENANT_MISMATCH
non-admin admin API  -> 403 ADMIN_ACCESS_REQUIRED
```

---

## Password reset flow

Request reset:

```bash
curl -X POST 'http://192.168.56.100:6060/v1/password/forgot' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{"email":"jakir@example.com"}'
```

Important: `request_id` is tracing metadata and is **not** the reset token. In non-production, if the user exists, the response may include `data.reset_token` for local testing. In production, the token must not be returned by the API.

Reset with either field name:

```bash
curl -X POST 'http://192.168.56.100:6060/v1/password/reset' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "reset_token": "<copy data.reset_token>",
    "new_password": "NewSecret123!"
  }'
```

Alias also works:

```json
{
  "token": "<copy data.reset_token>",
  "new_password": "NewSecret123!"
}
```

The reset token state is stored in Redis, password hash is updated in PostgreSQL, the Redis token is deleted, and an audit/Kafka event is created.

---

## Admin approval flow

1. User submits `/v1/admin/register` or `/v1/signup` with `account_type=admin`.
2. Existing approved admin signs in.
3. Approved admin lists requests:

```bash
curl -i 'http://192.168.56.100:6060/v1/admin/requests' \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}"
```

4. Approved admin decides:

```bash
curl -X POST 'http://192.168.56.100:6060/v1/admin/requests/<user_id>/decision' \
  -H "Authorization: Bearer ${ADMIN_ACCESS_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{
    "decision": "approve",
    "reason": "Verified request"
  }'
```

Decision must be `approve` or `reject`. The service updates PostgreSQL, writes audit, writes S3 audit snapshot, and emits an admin decision event through Kafka outbox.

---

## JWT claim contract

Access tokens include:

```json
{
  "iss": "auth",
  "aud": "micro-app",
  "sub": "user-id",
  "jti": "token-id",
  "username": "jakir",
  "email": "jakir@example.com",
  "role": "user",
  "admin_status": "not_requested",
  "tenant": "dev",
  "status": "active",
  "iat": 1710000000,
  "nbf": 1710000000,
  "exp": 1710000900
}
```

Allowed roles:

```text
user | admin | service | system
```

Allowed admin statuses:

```text
not_requested | pending | approved | rejected | suspended
```

---

## PostgreSQL

Service schema:

```text
auth
```

Required tables:

```text
auth.auth_users
auth.auth_sessions
auth.auth_audit_events
auth.outbox_events
auth.kafka_inbox_events
```

The service does not create shared `public.outbox_events` or `public.kafka_inbox_events`. Outbox rows are committed in the same transaction as business state changes, then published asynchronously to Kafka.

---

## Kafka

Published event topic:

```text
auth.events
```

Dead-letter topic:

```text
auth.events.dlq
```

Produced event types include:

```text
auth.user.signed_up
auth.user.signed_in
auth.user.logged_out
auth.token.refreshed
auth.password.reset_requested
auth.password.reset_completed
auth.password.changed
auth.admin.registration_requested
auth.admin.registration_approved
auth.admin.registration_rejected
```

Events are inserted into `auth.outbox_events` first. The publisher worker reads pending rows and publishes them to Kafka. Consumed events are deduplicated through `auth.kafka_inbox_events`.

---

## Redis

Redis key namespace:

```text
<environment>:auth_service:<purpose>:<id>
```

Examples:

```text
development:auth_service:session:<jti>
development:auth_service:token:blacklist:<jti>
development:auth_service:password-reset:<token_id>
```

Redis stores active session cache, access-token blacklist entries, password reset token state, and short-lived coordination state. It never stores raw passwords, raw access tokens, or raw refresh tokens.

---

## S3 / MinIO

Bucket:

```text
microservice
```

Audit snapshots are redacted and written under the configured audit prefix. S3 audit payloads never contain passwords, password hashes, access tokens, refresh tokens, authorization headers, secret keys, or private credentials.

---

## MongoDB structured logs

Database:

```text
db_micro_services
```

Collection naming:

```text
auth_service_development_logs
auth_service_stage_logs
auth_service_production_logs
```

Successful `/hello`, `/health`, and `/docs` requests are suppressed by default. Failed public system requests, auth failures, authorization denials, infrastructure failures, Kafka failures, S3 failures, and unhandled exceptions are logged.

---

## Elastic APM, Elasticsearch, and Kibana

The app initializes Elastic APM middleware and `elasticapm.instrument()` before serving traffic. APM captures HTTP transactions, exceptions, and dependency spans supported by the Elastic Python agent. The service also initializes an Elasticsearch client for health/observability checks and keeps Kibana URL/config available for operator dashboards.

Expected Kibana/APM views:

```text
Overview
Transactions
Dependencies
Errors
Metrics
Infrastructure
Service map
Logs
Alerts
Dashboards
Request traces
```

Application code sends APM transactions and structured logs. Kibana Infrastructure, Logs, Alerts, and Dashboards also require your Elastic Agent/Filebeat/Metricbeat/Docker/Kubernetes log and metric shipping pipeline to be installed outside this FastAPI container.

---

## Local quality checks

Run:

```bash
python -m compileall -q app tests scripts
python -m scripts.validate_env_contract
python -m app.preflight
python -m pytest -q
```

Expected test result for this package:

```text
16 passed
```

---

## Troubleshooting

### Swagger says “Failed to fetch”

OpenAPI uses same-origin `/`. Rebuild and hard refresh `/docs`. The request URL should match the page origin, for example:

```text
http://192.168.56.100:6060/hello
```

It should not call `http://localhost:8080/hello` from the browser.

### Password reset returns invalid token

Use `data.reset_token`, not `request_id`. `request_id` is only tracing metadata.

### APM service has no transactions

Check all of these:

1. The service was rebuilt with the current package.
2. `AUTH_APM_SERVER_URL` points to a reachable APM server.
3. `AUTH_APM_SECRET_TOKEN` matches APM server configuration.
4. Generate traffic after startup: `/hello`, `/health`, `/v1/signin`, `/v1/me`, `/v1/password/forgot`.
5. In Kibana APM, set time range to the last 15 minutes and environment to `development` or `All`.
6. Confirm Elastic Agent/log shipping separately for infrastructure/log dashboards.

### Docker build fails around Kafka package

This rebuild uses `aiokafka==0.14.0`, which provides Python 3.14 wheels. The Dockerfile also includes build dependencies in the builder stage to avoid native build failures.

## Docker build performance

Use the cache-friendly command below for normal development builds:

```bash
./command.sh dev
```

Do not use `docker build --no-cache` unless you intentionally want Docker to redownload and reinstall every dependency. The Dockerfile copies `requirements.txt` before the source code so dependency installation remains cached while application code changes.

The image exposes only container port `8080`. For your VM workflow, `command.sh` maps host port `6060` to container port `8080` by default. Override it with:

```bash
HOST_PORT=8080 ./command.sh dev
```
