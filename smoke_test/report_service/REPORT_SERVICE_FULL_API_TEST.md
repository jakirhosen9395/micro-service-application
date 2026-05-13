# Report Service Full API Test Script

This package tests `report_service` as a standalone API and as part of the full microservice system.

Files:

```text
report_service_full_api_test.sh
report_service_full_api_test.env.example
REPORT_SERVICE_FULL_API_TEST.md
```

## Quick start

```bash
unzip report_service_full_api_test_package.zip
cp report_service_full_api_test.env.example report_service_full_api_test.env
chmod +x report_service_full_api_test.sh
./report_service_full_api_test.sh ./report_service_full_api_test.env
```

## Environment pairing

Use matching service environments. Do not test dev `report_service` with prod `auth_service`, because the JWT tenant will not match.

```text
dev:   auth 6060, report 5050, calculator 2020, todo 3030, admin 1010, user 4040
stage: auth 6061, report 5051, calculator 2021, todo 3031, admin 1011, user 4041
prod:  auth 6062, report 5052, calculator 2022, todo 3032, admin 1012, user 4042
```

## What the script tests

### Public/system routes

- `GET /hello`
- `GET /health`
- `GET /docs`
- rejected public routes such as `/`, `/live`, `/ready`, `/healthy`, `/openapi.json`, `/swagger`, `/redoc`

### Authentication and authorization

- Missing JWT returns `401`.
- Invalid JWT returns `401`.
- Normal user is blocked from management/admin-only report APIs with `403`.
- Approved admin JWT is accepted for admin-only report APIs when available.

### Auth service integration

- `GET /hello`
- `GET /health`
- `POST /v1/signup`
- `POST /v1/signin`
- `GET /v1/me`
- `GET /v1/verify`

The Auth service is used to create realistic JWTs for normal user, second user, and approved admin flows.

### Cross-service data seeding

When enabled, the script seeds source data through:

- `calculator_service`: `GET /v1/calculator/operations`, `POST /v1/calculator/calculate`, `GET /v1/calculator/history`
- `todo_list_service`: `POST /v1/todos`, `GET /v1/todos`, `POST /v1/todos/{id}/complete`
- `user_service`: `GET /v1/users/me`, `GET /v1/users/me/dashboard`, projected calculations/todos/reports
- `admin_service`: report projections and summary endpoints

These checks help validate that Auth-issued JWTs work across services and that report projections can be requested using data produced by other services.

### Report service APIs

The script covers report types, report request lifecycle, status/read endpoints, preview/download/metadata, retry/cancel/delete, template routes, schedule routes, queue summary, and audit routes.

It also tests invalid request bodies, malformed JSON, unsupported report types, unsupported formats, missing IDs, cross-user access denial, and response-code coverage for `200`, `201`, `400`, `401`, `403`, `404`, and `409` where the implementation supports those states.

## Template and schedule behavior

The canonical contract allows template and schedule write APIs to be disabled with `501`. Some builds implement them. Configure:

```dotenv
REPORT_TEST_TEMPLATE_MODE=auto
REPORT_TEST_SCHEDULE_MODE=auto
```

Modes:

- `canonical-disabled`: expect write APIs to return `501`.
- `enabled`: expect create/update/activate/pause/resume/delete to work.
- `auto`: accept either implemented or disabled behavior.

## Stage/prod HTTPS enforcement

If your stage/prod env has `*_SECURITY_REQUIRE_HTTPS=true`, set forwarded proto headers in the test env:

```dotenv
REPORT_FORWARDED_PROTO=https
AUTH_FORWARDED_PROTO=https
CALCULATOR_FORWARDED_PROTO=https
TODO_FORWARDED_PROTO=https
ADMIN_FORWARDED_PROTO=https
USER_FORWARDED_PROTO=https
```

The script will send `X-Forwarded-Proto: https` for those services.

## Useful options

Verbose responses:

```dotenv
REPORT_TEST_VERBOSE=1
```

Keep response files:

```dotenv
REPORT_TEST_SAVE_RESPONSES=1
```

Wait for report completion:

```dotenv
REPORT_TEST_WAIT_COMPLETED=1
REPORT_TEST_COMPLETION_RETRIES=24
REPORT_TEST_COMPLETION_DELAY_SECONDS=5
```

Run mutation checks:

```dotenv
REPORT_TEST_MUTATE=1
```

## Interpreting results

A successful run ends with:

```text
All required report service checks passed.
```

If checks fail, the script prints the endpoint, expected status code, actual status code, and a redacted response summary. Tokens, secrets, passwords, and authorization headers are redacted from output.
