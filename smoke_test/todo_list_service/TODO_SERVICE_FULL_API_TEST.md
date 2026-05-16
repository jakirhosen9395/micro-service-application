# Todo Service Full API + Integration Test

This package contains a Bash-based test runner for `todo_list_service` / `todo_service`. It validates the canonical public routes, protected `/v1/todos/**` APIs, valid and invalid request bodies, JWT behavior, admin hard-delete authorization, and optional downstream projections through Admin, User, and Report services.

## Files

```text
todo_service_full_api_test.sh
todo_service_full_api_test.env.example
TODO_SERVICE_FULL_API_TEST.md
```

## Requirements

Install these on the machine where you run the test:

```bash
curl
python3
```

The script expects the services to be reachable over HTTP from the test machine.

## Quick start

```bash
unzip todo_service_full_api_test_package.zip
cp todo_service_full_api_test.env.example todo_service_full_api_test.env
chmod +x todo_service_full_api_test.sh
./todo_service_full_api_test.sh ./todo_service_full_api_test.env
```

## Environment configuration

For development, use matching service environments:

```dotenv
TODO_BASE_URL=http://3.108.225.164:3030
AUTH_BASE_URL=http://3.108.225.164:6060
ADMIN_BASE_URL=http://3.108.225.164:1010
USER_BASE_URL=http://3.108.225.164:4040
REPORT_BASE_URL=http://3.108.225.164:5050
TODO_TEST_TENANT=dev
```

Use matching service pairs only:

```text
dev:   auth 6060, todo 3030, admin 1010, user 4040, report 5050
stage: auth 6061, todo 3031, admin 1011, user 4041, report 5051
prod:  auth 6062, todo 3032, admin 1012, user 4042, report 5052
```

For stage/prod tested through local plain-HTTP host ports, set forwarded proto headers so services with HTTPS enforcement accept requests:

```dotenv
TODO_FORWARDED_PROTO=https
AUTH_FORWARDED_PROTO=https
ADMIN_FORWARDED_PROTO=https
USER_FORWARDED_PROTO=https
REPORT_FORWARDED_PROTO=https
```

## Main settings

```dotenv
TODO_TEST_TIMEOUT=25
TODO_TEST_VERBOSE=0
TODO_TEST_RUN_DOWNSTREAM=1
TODO_TEST_RUN_MUTATIONS=1
TODO_TEST_EVENT_WAIT_SECONDS=3
TODO_TEST_REPORT_FORMAT=pdf
TODO_TEST_REPORT_TYPE=
```

- `TODO_TEST_VERBOSE=1` prints response bodies for troubleshooting.
- `TODO_TEST_RUN_DOWNSTREAM=0` disables Admin/User/Report projection checks.
- `TODO_TEST_RUN_MUTATIONS=0` disables soft-delete/restore and admin hard-delete checks.
- `TODO_TEST_EVENT_WAIT_SECONDS` controls how long the script waits for Kafka projections before downstream checks.
- `TODO_TEST_REPORT_TYPE` can force a report type when report-service discovery cannot find a todo-related report type.

## What the script tests

### Public and rejected routes

- `GET /hello`
- `GET /health`
- `GET /docs`
- `GET /`
- `GET /live`
- `GET /ready`
- `GET /healthy`
- `GET /openapi.json`

### JWT behavior

- Missing token on `/v1/todos` returns `401`.
- Invalid token on `/v1/todos` returns `401`.
- Generated Auth user token can access Todo APIs.
- Bootstrap admin token can hard-delete todos.

### Valid Todo flows

- `POST /v1/todos`
- `GET /v1/todos`
- `GET /v1/todos?status=PENDING&priority=HIGH`
- `GET /v1/todos/today`
- `GET /v1/todos/overdue`
- `GET /v1/todos/{id}`
- `PUT /v1/todos/{id}`
- `PATCH /v1/todos/{id}/status`
- `GET /v1/todos/{id}/history`
- `POST /v1/todos/{id}/complete`
- `POST /v1/todos/{id}/archive`
- `POST /v1/todos/{id}/restore`
- `DELETE /v1/todos/{id}`
- `DELETE /v1/todos/{id}/hard`

### Invalid Todo flows

- Create with empty title.
- Create with invalid priority.
- Create with malformed JSON.
- Get missing todo.
- Invalid status transition.
- Normal user hard-delete forbidden.

### Optional downstream checks

When downstream service URLs are configured and `TODO_TEST_RUN_DOWNSTREAM=1`, the script checks:

Admin service:

- `GET /v1/admin/dashboard`
- `GET /v1/admin/todos/summary`
- `GET /v1/admin/todos`
- `GET /v1/admin/todos/users/{userId}`
- `GET /v1/admin/todos/{todoId}`

User service:

- `GET /v1/users/me`
- `GET /v1/users/me/todos`
- `GET /v1/users/me/todos/summary`
- `GET /v1/users/me/todos/activity`
- `GET /v1/users/me/todos/{todoId}`
- `GET /v1/users/{targetUserId}/todos` without grant expects forbidden/not found.

Report service:

- `GET /v1/reports/types`
- Selects the first todo-related report type if possible.
- `POST /v1/reports`
- `GET /v1/reports/{reportId}`

## Troubleshooting

### Health is `503`

`/health` returning `503` means one required dependency is down or unreachable. Check PostgreSQL, Redis, Kafka, S3/MinIO, MongoDB, APM, and Elasticsearch.

### Stage/prod returns `400` over HTTP

If stage/prod env files have HTTPS enforcement enabled, set forwarded proto values in the test env file:

```dotenv
TODO_FORWARDED_PROTO=https
AUTH_FORWARDED_PROTO=https
ADMIN_FORWARDED_PROTO=https
USER_FORWARDED_PROTO=https
REPORT_FORWARDED_PROTO=https
```

### Downstream projection returns `404`

Projection checks can need Kafka processing time. Increase:

```dotenv
TODO_TEST_EVENT_WAIT_SECONDS=8
```

### Report type not found

Set a known report type manually:

```dotenv
TODO_TEST_REPORT_TYPE=todo_summary_report
```

## Exit codes

- `0`: all required checks passed.
- `1`: at least one required check failed.
- `2`: script configuration problem, such as missing env file or missing command.
