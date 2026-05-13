# user_service Swagger and API Test Plan

## Swagger inventory

| Metric | Count |
|---|---:|
| Public system paths | 3 |
| Protected `/v1/users/**` paths | 34 |
| Total OpenAPI paths | 37 |
| Public operations | 3 |
| Protected operations | 39 |
| Total operations/APIs | 42 |
| Operations with JSON request bodies | 5 |
| Documented response status codes | 10 |

## Response status codes documented in Swagger

| Code | Meaning | Envelope |
|---:|---|---|
| 200 | Success | Success envelope |
| 201 | Created | Success envelope |
| 400 | Validation error / invalid query / malformed JSON | Error envelope |
| 401 | Missing/invalid JWT | Error envelope |
| 403 | Forbidden / tenant mismatch / suspended user / cross-user no grant | Error envelope |
| 404 | Unknown route or missing resource | Error envelope |
| 405 | Wrong HTTP method | Error envelope |
| 409 | Non-cancellable access/report request state | Error envelope |
| 500 | Internal server error | Error envelope |
| 503 | Health dependency down | Health envelope |

## APIs with request bodies

| Method | Path | Body purpose |
|---|---|---|
| PATCH | `/v1/users/me` | Profile patch |
| PUT | `/v1/users/me/preferences` | Preference replacement |
| POST | `/v1/users/access-requests` | Cross-user access request |
| POST | `/v1/users/me/reports` | Own report request |
| POST | `/v1/users/{targetUserId}/reports` | Cross-user report request |

## Invalid cases tested by `user_service_api_full_smoke_test.sh`

- Missing token: `GET /v1/users/me` returns `401`.
- Invalid token: `GET /v1/users/me` returns `401`.
- Rejected public routes: `/`, `/live`, `/ready`, `/healthy` return `404`.
- Wrong method: `POST /hello` and `DELETE /v1/users/me` return `405`.
- Invalid query strings:
  - `limit=abc` returns `400`.
  - `limit=0` returns `400`.
  - `limit=101` returns `400`.
  - `offset=abc` returns `400`.
  - `offset=-1` returns `400`.
- Malformed JSON body returns `400`.
- Missing required access request fields returns `400`.
- Access request TTL above maximum returns `400`.
- Unsupported report format returns `400`.
- Cross-user reads without active grant return `403`.
- Missing calculation/todo/report/access request IDs return `404`.
- Cancelling an already-cancelled access request returns `409`.
- Cancelling an already-cancelled report request returns `409`.

## Run

```bash
chmod +x user_service_api_full_smoke_test.sh
./user_service_api_full_smoke_test.sh \
  --user-host 192.168.56.100 --user-port 4040 \
  --auth-host 192.168.56.100 --auth-port 6060 \
  --verbose
```
