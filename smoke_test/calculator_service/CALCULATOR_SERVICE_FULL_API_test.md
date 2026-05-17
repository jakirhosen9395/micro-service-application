# Calculator Service Full API Test Script

This package provides a full Bash-based test harness for `calculator_service`. It follows the same test style as the Auth and Admin service testers: a configurable env file, repeatable generated test users, redacted logs, clear pass/fail output, and optional cross-service projection checks.

## Files

```text
calculator_service_full_api_test.sh
calculator_service_full_api_test.env.example
CALCULATOR_SERVICE_FULL_API_TEST.md
```

## What it validates

The script validates the Calculator service from three angles.

### 1. Public and security contract

It checks:

```text
GET /hello
GET /health
GET /docs
GET /
GET /live
GET /ready
GET /healthy
GET /openapi.json
```

Expected behavior:

- `/hello`, `/health`, and `/docs` are public.
- `/`, `/live`, `/ready`, and `/healthy` return `404`.
- `/openapi.json` is not publicly exposed; depending on your strict-docs build it can return `404`, `401`, or `403`.
- `/v1/calculator/**` rejects missing or invalid tokens with `401`.

### 2. Calculator business APIs

It tests all canonical Calculator APIs:

```text
GET    /v1/calculator/operations
POST   /v1/calculator/calculate
GET    /v1/calculator/history
GET    /v1/calculator/history/{userId}
GET    /v1/calculator/records/{calculationId}
DELETE /v1/calculator/history
```

It sends valid requests for supported operations:

```text
ADD, SUBTRACT, MULTIPLY, DIVIDE, MODULO, POWER, SQRT, PERCENTAGE,
SIN, COS, TAN, LOG, LN, ABS, ROUND, FLOOR, CEIL, FACTORIAL
```

It also tests expression mode:

```json
{
  "expression": "sqrt(16)+(10+5)*3"
}
```

Invalid request tests include:

- Missing operation/expression.
- Unsupported operation.
- Divide by zero.
- Invalid operand count.
- Invalid expression.
- Too-long expression.
- Missing token.
- Invalid JWT.
- Cross-user history without a grant.

### 3. Cross-service communication checks

The Calculator service must communicate through Kafka and local projections, not synchronous calls. The script therefore uses other services as consumers/read models after Calculator events are emitted.

Optional checks include:

```text
admin_service:
  GET /v1/admin/calculations/summary
  GET /v1/admin/calculations
  GET /v1/admin/calculations/users/{userId}
  GET /v1/admin/calculations/{calculationId}

user_service:
  GET /v1/users/me/calculations
  GET /v1/users/me/calculations/{calculationId}
  GET /v1/users/{targetUserId}/calculations

report_service:
  GET  /v1/reports/types
  POST /v1/reports
  GET  /v1/reports/{reportId}
  GET  /v1/reports/{reportId}/metadata
```

These checks prove that Auth-issued JWTs work across services and that Calculator events are visible through downstream projections.

## Quick start

```bash
unzip calculator_service_full_api_test_package.zip
cp calculator_service_full_api_test.env.example calculator_service_full_api_test.env
chmod +x calculator_service_full_api_test.sh
./calculator_service_full_api_test.sh ./calculator_service_full_api_test.env
```

## Recommended dev URLs

Edit the env file like this for your usual local VM dev ports:

```dotenv
CALCULATOR_BASE_URL=http://52.66.197.225:2020
AUTH_BASE_URL=http://52.66.197.225:6060
ADMIN_BASE_URL=http://52.66.197.225:1010
USER_BASE_URL=http://52.66.197.225:4040
REPORT_BASE_URL=http://52.66.197.225:5050
CALCULATOR_TEST_TENANT=dev
```

Use matching environments. Do not test Calculator dev with Auth prod tokens.

```text
dev:   auth 6060, calculator 2020, admin 1010, user 4040, report 5050
stage: auth 6061, calculator 2021, admin 1011, user 4041, report 5051
prod:  auth 6062, calculator 2022, admin 1012, user 4042, report 5052
```

## Stage/prod over local HTTP ports

If stage or prod services enforce HTTPS but you are testing them through plain local HTTP host ports, set forwarded proto headers:

```dotenv
CALCULATOR_FORWARDED_PROTO=https
AUTH_FORWARDED_PROTO=https
ADMIN_FORWARDED_PROTO=https
USER_FORWARDED_PROTO=https
REPORT_FORWARDED_PROTO=https
```

That makes local `curl` requests behave like they came through an HTTPS reverse proxy.

## Important env settings

```dotenv
CALCULATOR_TEST_VERBOSE=0
CALCULATOR_TEST_EVENT_SETTLE_SECONDS=3
CALCULATOR_TEST_ENABLE_ADMIN_CHECKS=1
CALCULATOR_TEST_ENABLE_USER_CHECKS=1
CALCULATOR_TEST_ENABLE_REPORT_CHECKS=1
CALCULATOR_TEST_ENABLE_DELETE_HISTORY=1
```

Set verbose mode when debugging:

```bash
CALCULATOR_TEST_VERBOSE=1 ./calculator_service_full_api_test.sh ./calculator_service_full_api_test.env
```

Disable optional services if they are not running:

```dotenv
CALCULATOR_TEST_ENABLE_ADMIN_CHECKS=0
CALCULATOR_TEST_ENABLE_USER_CHECKS=0
CALCULATOR_TEST_ENABLE_REPORT_CHECKS=0
```

## Notes about generated data

The script creates two normal Auth users for each run:

```text
calc_owner_<timestamp-random>
calc_other_<timestamp-random>
```

It performs Calculator mutations only for the generated owner user. `DELETE /v1/calculator/history` clears only that generated user's calculation history.

## Expected result

A successful run ends with:

```text
Summary: <N> total, <N> passed, 0 failed, <M> skipped
All required calculator service checks passed.
```

Some optional projection-detail checks accept `404` because Kafka projection timing can vary. List and summary endpoints should return `200` when the dependent service is running and the token is valid.

## Troubleshooting

### `401` from Calculator APIs

The token is missing, malformed, expired, or signed with a different JWT secret. Make sure `AUTH_BASE_URL` and `CALCULATOR_BASE_URL` point to matching environments.

### `403` from cross-user history

Expected for the second normal user when no access grant exists. Approved admin JWTs should be able to read another user's history.

### `/health` returns `503`

The service is running but at least one dependency is down. Inspect the dependency object in the health response for `postgres`, `redis`, `kafka`, `s3`, `mongodb`, `apm`, or `elasticsearch`.

### Admin/User projection detail returns `404`

The event may not have been consumed yet, or the projection consumer is not running. Increase:

```dotenv
CALCULATOR_TEST_EVENT_SETTLE_SECONDS=10
```

### Stage/prod HTTP tests fail with `400`

Set the forwarded proto values to `https` in the env file.
