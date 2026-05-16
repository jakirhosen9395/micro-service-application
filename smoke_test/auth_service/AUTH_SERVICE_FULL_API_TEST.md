# Auth Service Full API + Integration Test Script

This package contains a full Bash-based API test for `auth_service`. It starts from the smoke-test flow you provided and expands it to validate all canonical Auth APIs, error handling, JWT/session behavior, admin approval workflow, and optional communication checks against the other services.

## Files

```text
auth_service_full_api_test.sh
auth_service_full_api_test.env.example
AUTH_SERVICE_FULL_API_TEST.md
```

## Requirements

The script requires:

```bash
curl
python3
```

It does not require `jq`.

## Quick start

```bash
chmod +x auth_service_full_api_test.sh
cp auth_service_full_api_test.env.example auth_service_full_api_test.env
./auth_service_full_api_test.sh ./auth_service_full_api_test.env
```

## Environment pairing

Use matching Auth/Admin environments. Do not test `admin dev` with `auth prod` tokens because the JWT `tenant` claim will not match and Admin will correctly return `403`.

```dotenv
# dev
AUTH_BASE_URL=http://3.108.225.164:6060
ADMIN_BASE_URL=http://3.108.225.164:1010
AUTH_TEST_TENANT=dev

# stage
AUTH_BASE_URL=http://3.108.225.164:6061
ADMIN_BASE_URL=http://3.108.225.164:1011
AUTH_TEST_TENANT=stage

# prod
AUTH_BASE_URL=http://3.108.225.164:6062
ADMIN_BASE_URL=http://3.108.225.164:1012
AUTH_TEST_TENANT=prod
```

## HTTPS forwarding for stage/prod local tests

If stage/prod services use plain local Docker port mapping but enforce HTTPS with settings like `*_SECURITY_REQUIRE_HTTPS=true`, configure forwarded-proto headers in the env file:

```dotenv
AUTH_TEST_AUTH_FORWARDED_PROTO=https
AUTH_TEST_ADMIN_FORWARDED_PROTO=https
AUTH_TEST_USER_FORWARDED_PROTO=https
AUTH_TEST_CALCULATOR_FORWARDED_PROTO=https
AUTH_TEST_TODO_FORWARDED_PROTO=https
AUTH_TEST_REPORT_FORWARDED_PROTO=https
```

For dev, leave these blank unless dev also enforces HTTPS.

## What it tests

### Public Auth routes

- `GET /hello`
- `GET /health`
- `GET /docs`

It also verifies rejected routes:

- `GET /`
- `GET /live`
- `GET /ready`
- `GET /healthy`
- `GET /openapi.json` by default

If your Auth implementation intentionally exposes `/openapi.json`, set:

```dotenv
AUTH_TEST_EXPECT_OPENAPI_PUBLIC=1
```

### Protected route security

- `GET /v1/me` without token returns `401`
- `GET /v1/verify` without token returns `401`
- `GET /v1/admin/requests` without token returns `401`
- invalid bearer token returns `401`
- normal user token on admin-only endpoint returns `403`
- pending admin token on admin-only endpoint returns `403`

### Signup/signin/token APIs

- valid `POST /v1/signup`
- duplicate signup rejection
- invalid signup payloads
- valid `POST /v1/signin`
- invalid signin credentials
- valid `POST /v1/login` alias
- JWT claim validation for `iss`, `aud`, `sub`, `jti`, `role`, `tenant`
- `GET /v1/me`
- `GET /v1/verify`
- valid `POST /v1/token/refresh`
- old refresh-token reuse rejection
- invalid refresh-token rejection

### Password APIs

- `POST /v1/password/forgot`
- optional reset-token extraction
- `POST /v1/password/reset` when a reset token is returned
- signin with old password should fail after reset
- signin with new password should succeed after reset
- `POST /v1/password/change` with wrong current password fails
- `POST /v1/password/change` with correct current password succeeds
- signin after password change succeeds

For dev environments that must return reset tokens, set:

```dotenv
AUTH_TEST_EXPECT_RESET_TOKEN=1
```

For stage/prod, leave the default:

```dotenv
AUTH_TEST_EXPECT_RESET_TOKEN=auto
```

### Admin registration and decision flow

- invalid admin registration payload
- valid `POST /v1/admin/register`
- pending admin can sign in but has `admin_status=pending`
- pending admin cannot list admin requests
- bootstrap approved admin signin
- `GET /v1/admin/requests`
- invalid decision payload rejected
- approve pending admin through `POST /v1/admin/requests/{user_id}/decision`
- approved admin can sign in and has `admin_status=approved`
- second admin request is rejected for rejection-path coverage

### Logout/session revocation

- `POST /v1/logout`
- revoked access token fails on `GET /v1/me`
- revoked access token fails on `GET /v1/verify`

### Downstream service checks

When enabled, the script uses Auth-issued JWTs against other services to verify token compatibility and basic service communication.

```dotenv
AUTH_TEST_DOWNSTREAM_ENABLED=1
```

It checks:

- Admin service approved-admin access
- Admin service normal-user denial
- User service `/v1/users/me`
- Calculator service `/v1/calculator/operations`
- Todo service `/v1/todos`
- Report service `/v1/reports/types`

Mutation tests are disabled by default:

```dotenv
AUTH_TEST_DOWNSTREAM_MUTATE=0
```

Enable them to create real downstream records:

```dotenv
AUTH_TEST_DOWNSTREAM_MUTATE=1
```

When mutation tests are enabled, it attempts:

- calculator `POST /v1/calculator/calculate`
- todo `POST /v1/todos`
- report `POST /v1/reports`

## Useful commands

### Dev

```bash
./auth_service_full_api_test.sh ./auth_service_full_api_test.env
```

### Verbose output

```bash
AUTH_TEST_VERBOSE=1 ./auth_service_full_api_test.sh ./auth_service_full_api_test.env
```

### Keep response files

```bash
AUTH_TEST_SAVE_RESPONSES=1 AUTH_TEST_RESPONSE_DIR=./auth_test_responses ./auth_service_full_api_test.sh ./auth_service_full_api_test.env
```

### Stage over local HTTP ports with HTTPS enforcement

```dotenv
AUTH_BASE_URL=http://3.108.225.164:6061
ADMIN_BASE_URL=http://3.108.225.164:1011
AUTH_TEST_TENANT=stage
AUTH_TEST_AUTH_FORWARDED_PROTO=https
AUTH_TEST_ADMIN_FORWARDED_PROTO=https
```

```bash
./auth_service_full_api_test.sh ./auth_service_full_api_test.env
```

### Prod over local HTTP ports with HTTPS enforcement

```dotenv
AUTH_BASE_URL=http://3.108.225.164:6062
ADMIN_BASE_URL=http://3.108.225.164:1012
AUTH_TEST_TENANT=prod
AUTH_TEST_AUTH_FORWARDED_PROTO=https
AUTH_TEST_ADMIN_FORWARDED_PROTO=https
```

```bash
./auth_service_full_api_test.sh ./auth_service_full_api_test.env
```

## Reading failures

The script prints redacted response bodies on failures. Tokens, passwords, reset tokens, Authorization headers, and secret-like fields are redacted automatically.

Common failure causes:

| Failure | Likely cause |
|---|---|
| Admin endpoint returns `403` with admin token | Auth and Admin env mismatch, usually dev token used against stage/prod Admin or vice versa. |
| Health returns `503` | One required dependency is down: PostgreSQL, Redis, Kafka, S3, MongoDB, APM, or Elasticsearch. |
| Password reset skipped | The environment does not return reset tokens in API responses, which is expected for stage/prod. |
| Downstream User/Admin projection returns `404` | Kafka projection has not arrived yet, or downstream consumer is not running. Increase retry settings. |
| Stage/prod returns HTTP `400` over local HTTP | The service enforces HTTPS. Set `AUTH_TEST_*_FORWARDED_PROTO=https` for local tests or use a real HTTPS reverse proxy. |

## Exit code

- `0`: all required checks passed
- `1`: at least one required check failed
- `2`: script usage/dependency error
