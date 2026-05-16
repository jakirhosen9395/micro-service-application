# calculator_service

`calculator_service` is a Java 25 / Spring Boot 4.0.6 microservice for authenticated calculator operations, expression evaluation, calculation history, soft history clearing, PostgreSQL persistence, Redis caching, transactional Kafka outbox/inbox messaging, S3/MinIO audit snapshots, MongoDB structured logs, Elastic APM attachment, Elasticsearch health checking, and embedded interactive Swagger UI at `/docs`.

This rebuild follows the uploaded Unified Microservice Application Knowledge and Build Contract and mirrors the infrastructure style of the provided Auth and Admin services.

## Ownership

The service owns only calculator responsibilities:

- Authenticated calculation execution.
- Operation mode and expression mode.
- Calculation persistence in PostgreSQL schema `calculator`.
- Caller history and authorized cross-user history reads.
- Soft history clearing.
- Redis-backed calculation record/history caching.
- S3 audit snapshots for calculator actions.
- Kafka `calculator.events` publication through the transactional outbox pattern.
- Kafka inbox idempotency for consumed events.
- Local access-grant projection for cross-user grant checks from `access.events`.

It does not issue JWTs, hash passwords, or call Auth/Admin/User/Todo/Report services synchronously. JWT validation is local.

## Public and protected routes

Only these unauthenticated routes are public:

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/hello` | Service identity check. |
| `GET` | `/health` | Dependency health check. |
| `GET` | `/docs` | Embedded interactive Swagger UI. |

All business APIs are under `/v1/calculator/**` and require a valid Auth service JWT.

Rejected routes such as `/`, `/live`, `/ready`, `/healthy`, `/openapi.json`, `/v3/api-docs`, `/swagger-ui/**`, `/swagger-ui.html`, and `/actuator/**` are not registered as public service routes.

## Calculator API

Base path: `/v1/calculator`

| Method | Path | Auth | Description |
|---|---|---|---|
| `GET` | `/operations` | JWT | Lists supported operations. |
| `POST` | `/calculate` | JWT | Executes operation mode or expression mode. |
| `GET` | `/history?limit=50` | JWT | Returns caller history. |
| `GET` | `/history/{userId}?limit=50` | JWT | Returns another user's history when authorized. |
| `GET` | `/records/{calculationId}` | JWT | Returns one calculation record. |
| `DELETE` | `/history` | JWT | Soft-clears caller history. |

Cross-user history and record reads are allowed when one of these is true:

- Caller is the same user.
- Caller has `role=admin` and `admin_status=approved`.
- Caller has `role=service` or `role=system`.
- Caller has an active local projected grant for `calculator:history:read` from `access.events`.

## Supported operations

```text
ADD, SUBTRACT, MULTIPLY, DIVIDE, MODULO, POWER, SQRT, PERCENTAGE,
SIN, COS, TAN, LOG, LN, ABS, ROUND, FLOOR, CEIL, FACTORIAL
```

Notes:

- Trigonometric operations use degrees.
- `PERCENTAGE` expects `[percentage, value]`; `[10, 200]` returns `20`.
- `FACTORIAL` accepts non-negative integers up to `1000`.
- Division and modulo by zero return canonical `400` errors.
- Expression mode supports `+`, `-`, `*`, `/`, `%`, `^`, parentheses, `sqrt`, `power`, `sin`, `cos`, `tan`, `log`, `ln`, `abs`, `round`, `floor`, `ceil`, and `factorial`.

## Infrastructure summary

- PostgreSQL schema: `calculator`.
- Tables: `calculations`, `outbox_events`, `kafka_inbox_events`, `access_grant_projections`.
- Kafka topic: `calculator.events`.
- Kafka DLQ: `calculator.dead-letter`.
- Consumed topics: `auth.events`, `auth.admin.requests`, `auth.admin.decisions`, `admin.events`, `user.events`, `calculator.events`, `todo.events`, `report.events`, `access.events`.
- S3 bucket: `microservice`.
- S3 audit path: `calculator_service/<environment>/tenant/<tenant>/users/<actor_user_id>/events/<yyyy>/<MM>/<dd>/<HHmmss>_<event_type_slug>_<event_id>.json`.
- Redis namespace: `<environment>:calculator_service:`.
- MongoDB database: `micro_services_logs`.
- MongoDB collections: `calculator_service_development_logs`, `calculator_service_stage_logs`, `calculator_service_production_logs`.
- APM service name: `calculator_service`.

## Environment files

The repository includes `.env.dev`, `.env.stage`, `.env.prod`, and `.env.example`. All four files have the same keys in the same order. The README intentionally does not print secret values.

Fixed contract values include:

```text
CALC_SERVICE_NAME=calculator_service
CALC_PORT=8080
CALC_JWT_ISSUER=auth
CALC_JWT_AUDIENCE=micro-app
CALC_JWT_ALGORITHM=HS256
CALC_POSTGRES_SCHEMA=calculator
CALC_KAFKA_EVENTS_TOPIC=calculator.events
CALC_KAFKA_DEAD_LETTER_TOPIC=calculator.dead-letter
CALC_S3_BUCKET=microservice
CALC_LOG_FORMAT=pretty-json
CALC_LOGSTASH_ENABLED=false
CALC_FLYWAY_SCHEMA_HISTORY_TABLE=calculator_service_flyway_schema_history
```

No infrastructure boolean gates such as `CALC_KAFKA_ENABLED`, `CALC_S3_ENABLED`, `CALC_REDIS_ENABLED`, `CALC_POSTGRES_ENABLED`, `CALC_MONGO_ENABLED`, `CALC_APM_ENABLED`, `CALC_SWAGGER_ENABLED`, or `*_REQUIRED` variants are used.

## Build and run

Run tests:

```sh
mvn test
```

Build the app:

```sh
mvn -DskipTests package
docker build -t calculator_service:dev .
```

Run manually:

```sh
docker run -d --name calculator_service_dev --env-file .env.dev -p 2020:8080 calculator_service:dev
```

Or run the Auth/Admin-style script:

```sh
chmod +x command.sh
./command.sh
```

The script builds `latest`, `dev`, `stage`, and `prod`, then runs:

```text
calculator_service_dev   2020:8080
calculator_service_stage 2021:8080
calculator_service_prod  2022:8080
```

## Health check

`GET /health` returns the canonical dependency object with exactly these keys:

```text
jwt, postgres, redis, kafka, s3, mongodb, apm, elasticsearch
```

If any required dependency is down, `/health` returns HTTP `503` with top-level `status=down`. Secrets are never returned.

## Docs

`GET /docs` serves a human guide plus embedded Swagger UI. The OpenAPI document is embedded into that HTML response; generated `/openapi.json`, `/v3/api-docs`, and `/swagger-ui/**` routes are disabled.

Swagger UI enables:

```text
deepLinking, persistAuthorization, displayRequestDuration, tryItOutEnabled,
filter, docExpansion=list, model expansion, extensions, syntax highlighting,
and a requestInterceptor that adds X-Request-ID, X-Trace-ID, and X-Correlation-ID.
```

## Tests

The test suite covers calculator engine behavior, env contracts, Docker/command contracts, route exposure, JWT/security contracts, authorization rules, canonical event envelopes, S3 audit key format, Redis namespace expectations, MongoDB redaction, outbox/inbox schema and idempotency contracts, health dependency keys, and Swagger UI embedding.

## Runtime fix notes: outbox schema and APM visibility

This build includes a defensive `CalculatorSchemaInitializer` that creates the canonical `calculator` schema objects at startup and before outbox access. This fixes old/baselined deployments where Flyway history existed but `calculator.outbox_events` or `calculator.kafka_inbox_events` was missing.

The `/health` endpoint now emits explicit Elastic APM dependency spans for PostgreSQL, Redis, Kafka, S3, MongoDB, APM Server, and Elasticsearch. To populate Kibana quickly, run:

```bash
CALCULATOR_BASE_URL=http://192.168.56.50:2020 \
CALCULATOR_TOKEN='<valid-user-jwt>' \
COUNT=30 \
./observability/apm/generate_calculator_dependency_traffic.sh
```

Kibana views such as Overview, Transactions, Dependencies, Errors, Metrics, Logs, and Service map are populated from APM/log data. Infrastructure inventory, hosts, synthetics, TLS certificates, alerts, SLOs, cases, anomaly detection, streams, and custom dashboards require Kibana plus Elastic Agent/Metricbeat/Filebeat/Synthetics or saved-object setup outside this service container.
