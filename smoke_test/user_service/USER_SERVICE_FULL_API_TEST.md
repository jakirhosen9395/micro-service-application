# User Service Full API Test

This package tests `user_service` the same way as the Auth/Admin/Calculator/Todo/Report test packages: one Bash script, one env file, and one Markdown guide.

## Files

```text
user_service_full_api_test.sh
user_service_full_api_test.env.example
USER_SERVICE_FULL_API_TEST.md
```

## Quick start

```bash
unzip user_service_full_api_test_package.zip
cp user_service_full_api_test.env.example user_service_full_api_test.env
chmod +x user_service_full_api_test.sh
./user_service_full_api_test.sh ./user_service_full_api_test.env
```

## Environment matching

Use matching service environments. Do not test dev `user_service` with prod `auth_service`.

```text
dev:   auth 6060, user 4040, calculator 2020, todo 3030, admin 1010, report 5050
stage: auth 6061, user 4041, calculator 2021, todo 3031, admin 1011, report 5051
prod:  auth 6062, user 4042, calculator 2022, todo 3032, admin 1012, report 5052
```

Example dev env:

```dotenv
USER_BASE_URL=http://3.108.225.164:4040
AUTH_BASE_URL=http://3.108.225.164:6060
CALCULATOR_BASE_URL=http://3.108.225.164:2020
TODO_BASE_URL=http://3.108.225.164:3030
ADMIN_BASE_URL=http://3.108.225.164:1010
REPORT_BASE_URL=http://3.108.225.164:5050
```

For stage/prod over local HTTP host ports, set:

```dotenv
USER_FORWARDED_PROTO=https
AUTH_FORWARDED_PROTO=https
CALCULATOR_FORWARDED_PROTO=https
TODO_FORWARDED_PROTO=https
ADMIN_FORWARDED_PROTO=https
REPORT_FORWARDED_PROTO=https
```

## What the script tests

### Public system endpoints

- `GET /hello`
- `GET /health`
- `GET /docs`

It also checks rejected non-contract routes:

- `/`
- `/live`
- `/ready`
- `/healthy`
- `/openapi.json`
- `/v3/api-docs`
- `/swagger`
- `/swagger-ui`
- `/redoc`
- `/metrics`
- `/debug`

### Auth contract

- Missing token returns `401`
- Invalid token returns `401`
- Auth-issued JWT is accepted
- Normal user and second user are generated through `auth_service`
- Bootstrap approved admin token is generated through `auth_service`

### Profile and preferences

- `GET /v1/users/me`
- `PATCH /v1/users/me`
- malformed profile JSON
- `GET /v1/users/me/preferences`
- `PUT /v1/users/me/preferences`
- malformed preferences JSON
- invalid theme/body handling
- `GET /v1/users/me/activity`
- `GET /v1/users/me/dashboard`

### Extended User endpoints

Enabled by default through:

```dotenv
USER_TEST_EXPECT_EXTENDED_USER_ENDPOINTS=1
```

The script tests:

- `GET /v1/users/me/security-context`
- `GET /v1/users/me/rbac`
- `GET /v1/users/me/effective-permissions`

Set `USER_TEST_EXPECT_EXTENDED_USER_ENDPOINTS=0` if your current build does not expose those endpoints yet.

### Query validation

The script validates invalid `limit` and `offset` values on activity, reports, and access-request APIs.

### Calculator projections

If `CALCULATOR_BASE_URL` is set and `USER_TEST_SEED_CALCULATOR=1`, the script creates calculations through `calculator_service`, then checks:

- `GET /v1/users/me/calculations`
- `GET /v1/users/me/calculations/{calculationId}` when a calculation ID is returned
- missing calculation detail returns `404`

### Todo projections

If `TODO_BASE_URL` is set and `USER_TEST_SEED_TODO=1`, the script creates a todo through `todo_list_service`, then checks:

- `GET /v1/users/me/todos`
- `GET /v1/users/me/todos/summary`
- `GET /v1/users/me/todos/activity`
- `GET /v1/users/me/todos/{todoId}` when a todo ID is returned
- missing todo detail returns `404`

### Cross-user access rules

The script creates a second user and verifies that without a grant the second user cannot read the primary user's:

- calculations
- todos
- todo summary
- todo activity
- reports

If an approved-admin token is available, it also attempts admin cross-user reads.

### Access-request lifecycle

- missing body returns `400`
- TTL too far in the future returns `400`
- create access request with TTL inside the configured limit
- list access requests
- get access request
- cancel access request
- repeated cancel returns `409` or `404`
- missing access request returns `404`
- list access grants

Default TTL is safe for the canonical user service limit:

```dotenv
USER_TEST_ACCESS_REQUEST_TTL_DAYS=14
```

### User report-request lifecycle

- missing report body returns `400`
- unsupported report format returns `400`
- bad date order returns `400`
- create own report request
- list own reports
- get own report
- metadata/progress when supported
- cancel own report
- repeated cancel conflict
- missing report returns `404`
- optional admin target-user report request

### Report service compatibility

If `REPORT_BASE_URL` is set and `USER_TEST_SEED_REPORT=1`, the script creates a report through `report_service` and then checks user-service report projection/list APIs.

### Admin service compatibility

If `ADMIN_BASE_URL` and an admin token are available, the script checks admin projections for the generated user:

- user projection
- user activity
- user reports
- user calculations
- user todos

## Important flags

```dotenv
USER_TEST_VERBOSE=1
```

Print redacted response bodies for debugging.

```dotenv
USER_TEST_SAVE_RESPONSES=1
```

Keep all response JSON files and print their temp directory.

```dotenv
USER_TEST_SEED_CALCULATOR=0
USER_TEST_SEED_TODO=0
USER_TEST_SEED_REPORT=0
```

Disable cross-service seeding.

```dotenv
USER_TEST_REQUIRED_CODE_COVERAGE=0
```

Do not fail the run if a specific HTTP code is not observed.

## Expected output

A successful run ends with:

```text
Summary: <n> total, <n> passed, 0 failed, <n> skipped
All required user service checks passed.
```

Skips are acceptable when an optional downstream service URL is not provided or when a projection has not arrived yet through Kafka.

## Troubleshooting

### 401 on every protected route

The token is missing, invalid, expired, signed with the wrong secret, or from the wrong environment.

### 403 on cross-user routes

That is expected when no access grant exists and the caller is not approved admin/service.

### Stage/prod HTTP testing returns 400

Set forwarded proto values to `https` in the env file.

### Projection detail returns 404 after seeding

Kafka projection delivery can be asynchronous. The script accepts `200|404` for seeded projection detail where eventual consistency can apply.

### Auth signup returns 409

That is acceptable for reused usernames. The script signs in after signup and continues.
