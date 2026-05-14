# Admin Service Full API Test Script

This package contains a production-style Bash test runner for `admin_service`:

- `admin_service_full_api_test.sh`
- `admin_service_full_api_test.env.example`

The script validates the Admin service public system routes, rejected routes, authentication and authorization contract, every `/v1/admin/**` route, invalid input behavior, and optional cross-service seeding through Auth, User, Calculator, Todo, and Report services.

## What it tests

### Public system contract

The script verifies:

- `GET /hello` returns `200` and `status=ok`
- `GET /health` returns `200`, `status=ok`, and includes dependency keys:
  - `jwt`
  - `postgres`
  - `redis`
  - `kafka`
  - `s3`
  - `mongodb`
  - `apm`
  - `elasticsearch`
- `GET /docs` returns `200`
- rejected non-contract routes return `404`:
  - `/`
  - `/live`
  - `/ready`
  - `/healthy`
  - `/openapi.json`
  - `/swagger`
  - `/redoc`
  - `/swagger/index.html`
  - `/swagger/v1/swagger.json`

### Auth contract

The script signs in through `auth_service`, extracts an approved admin JWT, optionally creates normal users, and verifies:

- missing token returns `401`
- invalid token returns `401`
- normal user token returns `403`
- approved admin token returns `200`

### Cross-service seeding

When `ADMIN_TEST_SEED_OTHER_SERVICES=1`, the script calls other services to create or refresh local Admin projections through Kafka:

- `auth_service`: signin approved admin, signup/signin normal users
- `user_service`: current profile/dashboard and cross-user access-request flow
- `calculator_service`: operations and calculation execution
- `todo_list_service`: todo creation and completion
- `report_service`: report types and report request

After seeding, the script waits `ADMIN_TEST_PROJECTION_WAIT_SECONDS` seconds so Kafka consumers can update Admin projection tables.

### Admin read APIs

The script covers all known Admin read APIs, including:

- dashboard and summary
- admin registrations
- access requests and grants
- user projections, activity, dashboard, preferences, security context, RBAC, effective permissions, access requests, access grants, reports
- calculation projections, summaries, failures, history-cleared events, audit, user calculations, operation-specific calculations
- todo projections, summaries, overdue/today/archived/deleted lists, audit, user todo views, history
- reports, report types, templates, schedules, queue summary, audit, metadata, progress, events, files, preview, download-info
- admin audit

### Invalid input and mutation APIs

By default, the script is safe. With `ADMIN_TEST_MUTATE=0`, it tests mutation routes with missing IDs and expects `404`, `409`, or `501` depending on route semantics.

With `ADMIN_TEST_MUTATE=1`, the script uses discovered IDs where available and tests real side-effect APIs:

- suspend user
- activate user
- force password reset
- create report
- cancel/retry/regenerate report

Use mutation mode only on a disposable development/stage environment.

## Files

```text
admin_service_full_api_test.sh
admin_service_full_api_test.env.example
ADMIN_SERVICE_FULL_API_TEST.md
```

## Requirements

The machine running the script needs:

```bash
curl
python3
bash
```

The services should already be running and reachable from the test machine.

## Setup

Copy the env example:

```bash
cp admin_service_full_api_test.env.example admin_service_full_api_test.env
```

Edit values for your environment:

```dotenv
ADMIN_BASE_URL=http://52.66.223.53:1010
AUTH_BASE_URL=http://52.66.223.53:6060
USER_BASE_URL=http://52.66.223.53:4040
CALC_BASE_URL=http://52.66.223.53:2020
TODO_BASE_URL=http://52.66.223.53:3030
REPORT_BASE_URL=http://52.66.223.53:5050
```

Use matching service environments. Do not test Admin dev with Auth prod.

```text
dev:   admin 1010 + auth 6060
stage: admin 1011 + auth 6061
prod:  admin 1012 + auth 6062
```

## Run

```bash
chmod +x admin_service_full_api_test.sh
./admin_service_full_api_test.sh ./admin_service_full_api_test.env
```

Verbose mode:

```bash
ADMIN_TEST_VERBOSE=1 ./admin_service_full_api_test.sh ./admin_service_full_api_test.env
```

Keep response files:

```bash
ADMIN_TEST_SAVE_RESPONSES=1 ./admin_service_full_api_test.sh ./admin_service_full_api_test.env
```

Enable real mutations:

```bash
ADMIN_TEST_MUTATE=1 ./admin_service_full_api_test.sh ./admin_service_full_api_test.env
```

## Important HTTPS note for stage/prod

If stage/prod env files use:

```dotenv
ADMIN_SECURITY_REQUIRE_HTTPS=true
ADMIN_SECURITY_SECURE_COOKIES=true
```

but you test over local plain HTTP ports such as `1011` or `1012`, keep this env value enabled:

```dotenv
ADMIN_TEST_ADMIN_FORWARDED_PROTO=https
```

The script then sends:

```http
X-Forwarded-Proto: https
```

on Admin requests, matching how a reverse proxy would forward HTTPS requests.

## Key environment variables

| Variable | Purpose | Default |
|---|---|---:|
| `ADMIN_BASE_URL` | Admin service URL | `http://52.66.223.53:1010` |
| `AUTH_BASE_URL` | Auth service URL | `http://52.66.223.53:6060` |
| `USER_BASE_URL` | User service URL | empty / skipped |
| `CALC_BASE_URL` | Calculator service URL | empty / skipped |
| `TODO_BASE_URL` | Todo service URL | empty / skipped |
| `REPORT_BASE_URL` | Report service URL | empty / skipped |
| `ADMIN_TEST_AUTH_USERNAME` | Approved admin username/email | `admin` |
| `ADMIN_TEST_AUTH_PASSWORD` | Approved admin password | `admin123` |
| `ADMIN_TEST_AUTH_LOGIN_PATH` | Auth login path | `/v1/signin` |
| `ADMIN_TEST_AUTH_SIGNUP_PATH` | Auth signup path | `/v1/signup` |
| `ADMIN_TEST_CREATE_USERS` | Create normal users through Auth | `1` |
| `ADMIN_TEST_SEED_OTHER_SERVICES` | Call other services before Admin checks | `1` |
| `ADMIN_TEST_MUTATE` | Use real IDs for side-effect Admin APIs | `0` |
| `ADMIN_TEST_VERBOSE` | Print response bodies | `0` |
| `ADMIN_TEST_SAVE_RESPONSES` | Keep temp response files | `0` |
| `ADMIN_TEST_PROJECTION_WAIT_SECONDS` | Kafka projection wait after seeding | `8` |
| `ADMIN_TEST_ADMIN_FORWARDED_PROTO` | Header value for Admin requests | `https` |

## Reading results

At the end, the script prints a summary like:

```text
Summary: 120 total, 120 passed, 0 failed, 0 skipped
Admin Base URL:       http://52.66.223.53:1010
Auth Base URL:        http://52.66.223.53:6060
Mutation mode:        0
Discovered user id:   <id>
Discovered report id: <id>
```

If any test fails, the script exits with code `1`.

## Troubleshooting

### `HTTPS_REQUIRED` on `/hello`

Use:

```dotenv
ADMIN_TEST_ADMIN_FORWARDED_PROTO=https
```

or test dev where `ADMIN_SECURITY_REQUIRE_HTTPS=false`.

### Admin returns `403` for every protected endpoint

Usually this means you are using mismatched environments. For example, Admin dev on `1010` with Auth prod on `6062` gives a tenant mismatch.

Use matching pairs:

```text
1010 with 6060
1011 with 6061
1012 with 6062
```

### Projection IDs are missing

Make sure Kafka is running, the Admin consumer is healthy, and `ADMIN_TEST_SEED_OTHER_SERVICES=1`. Increase:

```dotenv
ADMIN_TEST_PROJECTION_WAIT_SECONDS=15
```

### Other services are not running

Leave their base URLs blank. The script will skip cross-service seeding for missing service URLs and still test Admin's own APIs.

