#!/usr/bin/env bash
# Todo List Service full API smoke/contract test script with retry support.
#
# This script is designed for the unified microservice application where:
#   - todo_list_service runs on host port 3030 by default
#   - auth_service runs on host port 6060 by default
#   - admin_service runs on host port 1010 by default
#
# Named parameter usage:
#   chmod +x todo_list_service_api_full_retry_test.sh
#   ./todo_list_service_api_full_retry_test.sh \
#     --todo-host 192.168.56.100 --todo-port 3030 \
#     --auth-host 192.168.56.100 --auth-port 6060 \
#     --admin-host 192.168.56.100 --admin-port 1010 \
#     --iterations 2 --retries 3
#
# URL usage:
#   ./todo_list_service_api_full_retry_test.sh \
#     --todo-url http://52.66.197.225:3030 \
#     --auth-url http://52.66.197.225:6060 \
#     --admin-url http://52.66.197.225:1010
#
# Environment variable input is also supported:
#   TODO_SERVICE_HOST=192.168.56.100 TODO_SERVICE_PORT=3030 \
#   AUTH_SERVICE_HOST=192.168.56.100 AUTH_SERVICE_PORT=6060 \
#   ADMIN_SERVICE_HOST=192.168.56.100 ADMIN_SERVICE_PORT=1010 \
#   TODO_TEST_ITERATIONS=2 TODO_TEST_RETRIES=3 \
#   ./todo_list_service_api_full_retry_test.sh
#
# Optional auth/test variables:
#   TODO_TEST_USERNAME=<existing-or-created-user>
#   TODO_TEST_PASSWORD=<password>
#   TODO_TEST_CREATE_USER=1
#   TODO_TEST_ADMIN_USERNAME=admin
#   TODO_TEST_ADMIN_PASSWORD=admin123
#   TODO_TEST_ACCESS_TOKEN=<preissued-user-jwt>
#   TODO_TEST_ADMIN_TOKEN=<preissued-admin-jwt>
#   TODO_TEST_AUTH_LOGIN_PATH=/v1/signin
#   TODO_TEST_TIMEOUT=20
#   TODO_TEST_RETRIES=3
#   TODO_TEST_RETRY_DELAY_SECONDS=2
#   TODO_TEST_ITERATIONS=2
#   TODO_TEST_VERBOSE=0
#   TODO_TEST_SAVE_RESPONSES=0
#   TODO_TEST_STRICT_PUBLIC_ROUTES=1
#   TODO_TEST_ADMIN_HARD_DELETE=1
#   TODO_TEST_RUN_ADMIN_SERVICE_CHECKS=1
#
# Exits non-zero if any required test fails. Optional/admin tests may be skipped.

set -u

usage() {
  cat <<'USAGE'
Usage:
  ./todo_list_service_api_full_retry_test.sh \
    --todo-host <ip> [--todo-port 3030] \
    --auth-host <ip> [--auth-port 6060] \
    [--admin-host <ip> --admin-port 1010] \
    [--iterations 2] [--retries 3]

  ./todo_list_service_api_full_retry_test.sh \
    --todo-url http://<ip>:3030 \
    --auth-url http://<ip>:6060 \
    [--admin-url http://<ip>:1010]

Named parameters:
  --todo-host <host>                  Todo service host/IP
  --todo-port <port>                  Todo service host port, default 3030
  --todo-url <url>                    Todo service base URL
  --auth-host <host>                  Auth service host/IP
  --auth-port <port>                  Auth service host port, default 6060
  --auth-url <url>                    Auth service base URL
  --admin-host <host>                 Admin service host/IP
  --admin-port <port>                 Admin service host port, default 1010
  --admin-url <url>                   Admin service base URL
  --iterations <n>                    Repeat full Todo API CRUD flow n times, default 2
  --retries <n>                       Retry each HTTP request n times, default 3
  --retry-delay-seconds <n>           Delay between retries, default 2
  --timeout <seconds>                 Curl max-time timeout, default 20
  --verbose                           Print response bodies
  --save-responses                    Keep response files in a temp directory
  -h, --help                          Show this help

Environment-variable input uses these names:
  TODO_SERVICE_HOST, TODO_SERVICE_PORT, TODO_SERVICE_URL
  AUTH_SERVICE_HOST, AUTH_SERVICE_PORT, AUTH_SERVICE_URL
  ADMIN_SERVICE_HOST, ADMIN_SERVICE_PORT, ADMIN_SERVICE_URL

Useful auth variables:
  TODO_TEST_USERNAME, TODO_TEST_PASSWORD, TODO_TEST_CREATE_USER
  TODO_TEST_ADMIN_USERNAME, TODO_TEST_ADMIN_PASSWORD
  TODO_TEST_ACCESS_TOKEN, TODO_TEST_ADMIN_TOKEN
USAGE
}

normalize_base_url() {
  local input="${1:-}"
  local port="${2:-}"
  if [ -z "$input" ]; then
    printf ''
    return 0
  fi
  if printf '%s' "$input" | grep -Eq '^https?://'; then
    printf '%s' "${input%/}"
  else
    printf 'http://%s:%s' "$input" "$port"
  fi
}

TODO_SERVICE_HOST="${TODO_SERVICE_HOST:-}"
TODO_SERVICE_PORT="${TODO_SERVICE_PORT:-3030}"
TODO_SERVICE_URL="${TODO_SERVICE_URL:-}"
AUTH_SERVICE_HOST="${AUTH_SERVICE_HOST:-}"
AUTH_SERVICE_PORT="${AUTH_SERVICE_PORT:-6060}"
AUTH_SERVICE_URL="${AUTH_SERVICE_URL:-}"
ADMIN_SERVICE_HOST="${ADMIN_SERVICE_HOST:-}"
ADMIN_SERVICE_PORT="${ADMIN_SERVICE_PORT:-1010}"
ADMIN_SERVICE_URL="${ADMIN_SERVICE_URL:-}"

TIMEOUT="${TODO_TEST_TIMEOUT:-20}"
REQUEST_RETRIES="${TODO_TEST_RETRIES:-3}"
RETRY_DELAY_SECONDS="${TODO_TEST_RETRY_DELAY_SECONDS:-2}"
ITERATIONS="${TODO_TEST_ITERATIONS:-2}"
VERBOSE="${TODO_TEST_VERBOSE:-0}"
SAVE_RESPONSES="${TODO_TEST_SAVE_RESPONSES:-0}"
STRICT_PUBLIC_ROUTES="${TODO_TEST_STRICT_PUBLIC_ROUTES:-1}"
AUTH_LOGIN_PATH="${TODO_TEST_AUTH_LOGIN_PATH:-/v1/signin}"
CREATE_USER="${TODO_TEST_CREATE_USER:-1}"
CREATE_SECOND_USER="${TODO_TEST_CREATE_SECOND_USER:-1}"
RUN_ADMIN_SERVICE_CHECKS="${TODO_TEST_RUN_ADMIN_SERVICE_CHECKS:-1}"
ADMIN_HARD_DELETE="${TODO_TEST_ADMIN_HARD_DELETE:-1}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --todo-host) TODO_SERVICE_HOST="${2:-}"; shift 2 ;;
    --todo-port) TODO_SERVICE_PORT="${2:-3030}"; shift 2 ;;
    --todo-url) TODO_SERVICE_URL="${2:-}"; shift 2 ;;
    --auth-host) AUTH_SERVICE_HOST="${2:-}"; shift 2 ;;
    --auth-port) AUTH_SERVICE_PORT="${2:-6060}"; shift 2 ;;
    --auth-url) AUTH_SERVICE_URL="${2:-}"; shift 2 ;;
    --admin-host) ADMIN_SERVICE_HOST="${2:-}"; shift 2 ;;
    --admin-port) ADMIN_SERVICE_PORT="${2:-1010}"; shift 2 ;;
    --admin-url) ADMIN_SERVICE_URL="${2:-}"; shift 2 ;;
    --iterations) ITERATIONS="${2:-2}"; shift 2 ;;
    --retries) REQUEST_RETRIES="${2:-3}"; shift 2 ;;
    --retry-delay-seconds) RETRY_DELAY_SECONDS="${2:-2}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-20}"; shift 2 ;;
    --verbose) VERBOSE=1; shift 1 ;;
    --save-responses) SAVE_RESPONSES=1; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

if [ -z "$TODO_SERVICE_URL" ]; then
  TODO_SERVICE_URL="$(normalize_base_url "$TODO_SERVICE_HOST" "$TODO_SERVICE_PORT")"
fi
if [ -z "$AUTH_SERVICE_URL" ]; then
  AUTH_SERVICE_URL="$(normalize_base_url "$AUTH_SERVICE_HOST" "$AUTH_SERVICE_PORT")"
fi
if [ -z "$ADMIN_SERVICE_URL" ]; then
  ADMIN_SERVICE_URL="$(normalize_base_url "$ADMIN_SERVICE_HOST" "$ADMIN_SERVICE_PORT")"
fi

if [ -z "$TODO_SERVICE_URL" ] || [ -z "$AUTH_SERVICE_URL" ]; then
  echo "Missing required Todo/Auth service input. Use --todo-host/--auth-host or --todo-url/--auth-url."
  usage
  exit 2
fi

case "$ITERATIONS" in ''|*[!0-9]*) echo "--iterations must be a positive integer"; exit 2 ;; esac
case "$REQUEST_RETRIES" in ''|*[!0-9]*) echo "--retries must be a positive integer"; exit 2 ;; esac
case "$RETRY_DELAY_SECONDS" in ''|*[!0-9]*) echo "--retry-delay-seconds must be a non-negative integer"; exit 2 ;; esac
[ "$ITERATIONS" -lt 1 ] && ITERATIONS=1
[ "$REQUEST_RETRIES" -lt 1 ] && REQUEST_RETRIES=1

ADMIN_USERNAME="${TODO_TEST_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${TODO_TEST_ADMIN_PASSWORD:-admin123}"
ACCESS_TOKEN="${TODO_TEST_ACCESS_TOKEN:-}"
ADMIN_TOKEN="${TODO_TEST_ADMIN_TOKEN:-}"
SECOND_TOKEN="${TODO_TEST_SECOND_TOKEN:-}"

RUN_ID="$(date +%s)-$RANDOM"
TEST_USERNAME="${TODO_TEST_USERNAME:-todouser_${RUN_ID}}"
TEST_EMAIL="${TEST_USERNAME}@example.com"
TEST_PASSWORD="${TODO_TEST_PASSWORD:-Test1234!Aa}"
SECOND_USERNAME="todoother_${RUN_ID}"
SECOND_EMAIL="${SECOND_USERNAME}@example.com"
SECOND_PASSWORD="Test1234!Aa"

TMP_DIR="$(mktemp -d)"
if [ "$SAVE_RESPONSES" = "1" ]; then
  echo "Response files will be kept at: $TMP_DIR"
else
  trap 'rm -rf "$TMP_DIR"' EXIT
fi

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TEST_COUNT=0
USER_ID=""
ADMIN_USER_ID=""
SECOND_USER_ID=""
LAST_TODO_ID=""

if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
  GREEN="$(tput setaf 2)"
  RED="$(tput setaf 1)"
  YELLOW="$(tput setaf 3)"
  BLUE="$(tput setaf 4)"
  BOLD="$(tput bold)"
  RESET="$(tput sgr0)"
else
  GREEN=""; RED=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
fi

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 2
  fi
}
need_cmd curl
need_cmd python3

new_uuid() {
  python3 - <<'PY'
import uuid
print(str(uuid.uuid4()))
PY
}

safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_'
}

iso_utc_hours() {
  python3 - "$1" <<'PY'
from datetime import datetime, timezone, timedelta
import sys
hours = int(sys.argv[1])
print((datetime.now(timezone.utc) + timedelta(hours=hours)).replace(microsecond=0).isoformat().replace('+00:00', 'Z'))
PY
}

iso_utc_date() {
  python3 - "$1" <<'PY'
from datetime import datetime, timezone, timedelta
import sys
days = int(sys.argv[1])
print((datetime.now(timezone.utc) + timedelta(days=days)).date().isoformat())
PY
}

jwt_claim() {
  python3 - "$1" "$2" <<'PY'
import base64, json, sys
jwt, claim = sys.argv[1], sys.argv[2]
try:
    parts = jwt.split('.')
    payload = parts[1] + '=' * (-len(parts[1]) % 4)
    obj = json.loads(base64.urlsafe_b64decode(payload.encode()).decode())
    val = obj.get(claim, '')
    print(json.dumps(val, separators=(',', ':')) if isinstance(val, (dict, list)) else val)
except Exception:
    print('')
PY
}

json_get() {
  python3 - "$1" "$2" <<'PY'
import json, sys
file_path, key_path = sys.argv[1], sys.argv[2]
try:
    raw = open(file_path, 'r', encoding='utf-8').read()
    if not raw.strip():
        print('')
        sys.exit(0)
    obj = json.loads(raw)
    for key in key_path.split('.'):
        if not key:
            continue
        if isinstance(obj, list):
            obj = obj[int(key)]
        elif isinstance(obj, dict):
            obj = obj.get(key)
        else:
            obj = None
        if obj is None:
            print('')
            sys.exit(0)
    print(json.dumps(obj, separators=(',', ':')) if isinstance(obj, (dict, list)) else obj)
except Exception:
    print('')
PY
}

json_get_any() {
  local file="$1"
  shift
  local value path
  for path in "$@"; do
    value="$(json_get "$file" "$path")"
    if [ "$value" != "" ]; then
      printf '%s' "$value"
      return 0
    fi
  done
  printf ''
}

json_status() {
  json_get "$1" "status"
}

short_body() {
  python3 - "$1" <<'PY'
import json, sys
p = sys.argv[1]
try:
    data = open(p, 'r', encoding='utf-8').read()
    try:
        obj = json.loads(data)
        sensitive_words = ('token', 'secret', 'password', 'authorization', 'access_key', 'refresh')
        def redact(x):
            if isinstance(x, dict):
                return {k: ('<redacted>' if any(w in k.lower() for w in sensitive_words) else redact(v)) for k, v in x.items()}
            if isinstance(x, list):
                return [redact(i) for i in x]
            return x
        print(json.dumps(redact(obj), indent=2)[:1600])
    except Exception:
        print(data[:1600])
except Exception as exc:
    print(f'<unable to read response: {exc}>')
PY
}

record_pass() {
  TEST_COUNT=$((TEST_COUNT + 1)); PASS_COUNT=$((PASS_COUNT + 1))
  printf "%s[PASS]%s %s\n" "$GREEN" "$RESET" "$1"
}

record_fail() {
  TEST_COUNT=$((TEST_COUNT + 1)); FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "%s[FAIL]%s %s\n" "$RED" "$RESET" "$1"
  [ "${2:-}" != "" ] && echo "       $2"
}

record_skip() {
  TEST_COUNT=$((TEST_COUNT + 1)); SKIP_COUNT=$((SKIP_COUNT + 1))
  printf "%s[SKIP]%s %s\n" "$YELLOW" "$RESET" "$1"
  [ "${2:-}" != "" ] && echo "       $2"
}

last_file() { cat "$TMP_DIR/$(safe_name "$1").path" 2>/dev/null || true; }
last_code() { cat "$TMP_DIR/$(safe_name "$1").code" 2>/dev/null || true; }

is_retryable_code() {
  case "$1" in
    000|408|409|425|429|500|502|503|504) return 0 ;;
    *) return 1 ;;
  esac
}

request_base() {
  # request_base <base_url> <name> <method> <path> <expected_codes_regex> <body_or_empty> <bearer_token_or_empty>
  local base_url="$1"
  local name="$2"
  local method="$3"
  local path="$4"
  local expected="$5"
  local body="${6:-}"
  local token="${7:-}"
  local safe outfile req_id trace_id accept_header http_code curl_exit attempt response_summary

  safe="$(safe_name "$name")"
  outfile="$TMP_DIR/${safe}.json"
  req_id="req-$(new_uuid | tr -d '-')"
  trace_id="trace-$(new_uuid | tr -d '-')"
  accept_header="application/json"
  [ "$path" = "/docs" ] && accept_header="text/html,application/xhtml+xml,*/*"

  attempt=1
  while [ "$attempt" -le "$REQUEST_RETRIES" ]; do
    local curl_args=(
      -sS
      --connect-timeout 5
      --max-time "$TIMEOUT"
      -o "$outfile"
      -w "%{http_code}"
      -X "$method"
      "$base_url$path"
      -H "accept: $accept_header"
      -H "X-Request-ID: $req_id"
      -H "X-Trace-ID: $trace_id"
      -H "X-Correlation-ID: $req_id"
    )
    if [ "$token" != "" ]; then
      curl_args+=( -H "Authorization: Bearer $token" )
    fi
    if [ "$body" != "" ]; then
      curl_args+=( -H "Content-Type: application/json" -d "$body" )
    fi

    http_code="$(curl "${curl_args[@]}" 2>"$outfile.curlerr")"
    curl_exit=$?
    echo "$outfile" > "$TMP_DIR/${safe}.path"
    echo "$http_code" > "$TMP_DIR/${safe}.code"

    if [ "$VERBOSE" = "1" ]; then
      echo "--- $name attempt $attempt response ($http_code) ---"
      short_body "$outfile"
      echo "----------------------------------------------"
    fi

    if [ "$curl_exit" -eq 0 ] && printf '%s' "$http_code" | grep -Eq "^($expected)$"; then
      record_pass "$name ($method $path -> HTTP $http_code, attempt $attempt)"
      return 0
    fi

    if [ "$attempt" -lt "$REQUEST_RETRIES" ] && { [ "$curl_exit" -ne 0 ] || is_retryable_code "$http_code"; }; then
      sleep "$RETRY_DELAY_SECONDS"
      attempt=$((attempt + 1))
      continue
    fi

    break
  done

  response_summary="$(short_body "$outfile" | tr '\n' ' ' | cut -c1-900)"
  if [ "$curl_exit" -ne 0 ]; then
    record_fail "$name ($method $path curl failed after $attempt attempt(s))" "$(cat "$outfile.curlerr" 2>/dev/null)"
  else
    record_fail "$name ($method $path expected HTTP $expected but got $http_code after $attempt attempt(s))" "response: $response_summary"
  fi
  return 1
}

todo_request() { request_base "$TODO_SERVICE_URL" "$@"; }
auth_request() { request_base "$AUTH_SERVICE_URL" "$@"; }
admin_request() { request_base "$ADMIN_SERVICE_URL" "$@"; }

assert_json_status_ok() {
  local name="$1" file status
  file="$(last_file "$name")"
  status="$(json_status "$file")"
  if [ "$status" = "ok" ]; then
    record_pass "$name envelope status is ok"
  else
    record_fail "$name envelope status" "expected status=ok, got '$status'. Body: $(short_body "$file" | tr '\n' ' ' | cut -c1-700)"
  fi
}

assert_json_status_error() {
  local name="$1" expected_error="$2" file status error_code
  file="$(last_file "$name")"
  status="$(json_get "$file" "status")"
  error_code="$(json_get "$file" "error_code")"
  if [ "$status" = "error" ] && printf '%s' "$error_code" | grep -Eq "^($expected_error)$"; then
    record_pass "$name error envelope is $error_code"
  else
    record_fail "$name error envelope" "expected status=error and error_code=$expected_error, got status=$status error_code=$error_code. Body: $(short_body "$file" | tr '\n' ' ' | cut -c1-700)"
  fi
}

assert_health_shape() {
  local name="$1" file rc
  file="$(last_file "$name")"
  python3 - "$file" <<'PY'
import json, sys
required = ['jwt','postgres','redis','kafka','s3','mongodb','apm','elasticsearch']
try:
    obj = json.load(open(sys.argv[1], encoding='utf-8'))
    deps = obj.get('dependencies') or {}
    missing = [k for k in required if k not in deps]
    bad = [k for k, v in deps.items() if not isinstance(v, dict) or 'status' not in v or 'latency_ms' not in v]
    if missing or bad:
        print('missing=' + ','.join(missing) + ' bad=' + ','.join(bad))
        sys.exit(1)
except Exception as exc:
    print(str(exc)); sys.exit(1)
PY
  rc=$?
  if [ "$rc" -eq 0 ]; then
    record_pass "$name health dependency shape"
  else
    record_fail "$name health dependency shape" "$(short_body "$file" | tr '\n' ' ' | cut -c1-800)"
  fi
}

extract_todo_id() {
  local name="$1" file
  file="$(last_file "$name")"
  json_get_any "$file" \
    "data.id" \
    "data.todo.id" \
    "data.todo.todo_id" \
    "data.todo_id" \
    "id" \
    "todo_id"
}

print_header() {
  echo "${BOLD}${BLUE}Todo List Service Full API Retry Test${RESET}"
  echo "Todo Base URL:       $TODO_SERVICE_URL"
  echo "Auth Base URL:       $AUTH_SERVICE_URL"
  echo "Admin Base URL:      ${ADMIN_SERVICE_URL:-<not provided>}"
  echo "Auth Login Path:     $AUTH_LOGIN_PATH"
  echo "Iterations:          $ITERATIONS"
  echo "Retries/request:     $REQUEST_RETRIES"
  echo "Retry delay seconds: $RETRY_DELAY_SECONDS"
  echo "Timeout seconds:     $TIMEOUT"
  echo "Run ID:              $RUN_ID"
  echo
}

wait_for_todo() {
  local i max=12
  echo "Waiting for Todo service /hello..."
  for i in $(seq 1 "$max"); do
    if todo_request "wait todo hello $i" "GET" "/hello" "200" "" "" >/dev/null 2>&1; then
      record_pass "Todo service is reachable via /hello"
      return 0
    fi
    sleep 2
  done
  record_fail "Todo service reachable via /hello" "Expected public GET /hello to return 200. This often means JwtAuthenticationFilter is still protecting /hello."
  return 1
}

signup_user() {
  local username="$1" email="$2" password="$3" full_name="$4" body
  body=$(cat <<JSON
{
  "username": "$username",
  "email": "$email",
  "password": "$password",
  "full_name": "$full_name",
  "birthdate": "1998-05-20",
  "gender": "male",
  "account_type": "user"
}
JSON
)
  auth_request "auth signup $username" "POST" "/v1/signup" "200|201|409" "$body" ""
}

signin_user() {
  local username="$1" password="$2" device="$3" name="$4" body
  body=$(cat <<JSON
{
  "username_or_email": "$username",
  "password": "$password",
  "device_id": "$device"
}
JSON
)
  auth_request "$name" "POST" "$AUTH_LOGIN_PATH" "200" "$body" ""
}

login_primary_user() {
  if [ "$ACCESS_TOKEN" != "" ]; then
    USER_ID="$(jwt_claim "$ACCESS_TOKEN" "sub")"
    record_pass "primary user token provided by TODO_TEST_ACCESS_TOKEN"
    return 0
  fi
  if [ "$CREATE_USER" = "1" ]; then
    signup_user "$TEST_USERNAME" "$TEST_EMAIL" "$TEST_PASSWORD" "Todo Full API Test User"
  fi
  signin_user "$TEST_USERNAME" "$TEST_PASSWORD" "todo-full-$RUN_ID" "auth primary user signin"
  local file
  file="$(last_file "auth primary user signin")"
  ACCESS_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  USER_ID="$(json_get_any "$file" "data.user.id" "data.user.user_id" "user.id" "user.user_id" "sub")"
  [ "$USER_ID" = "" ] && USER_ID="$(jwt_claim "$ACCESS_TOKEN" "sub")"
  if [ "$ACCESS_TOKEN" = "" ]; then
    record_fail "primary user access token extracted" "No token found. Set TODO_TEST_USERNAME/TODO_TEST_PASSWORD or TODO_TEST_ACCESS_TOKEN."
    return 1
  fi
  record_pass "primary user access token extracted"
  [ "$USER_ID" != "" ] && record_pass "primary user id extracted: $USER_ID" || record_skip "primary user id extracted" "not present in token/response"
}

login_admin_token() {
  if [ "$ADMIN_TOKEN" != "" ]; then
    ADMIN_USER_ID="$(jwt_claim "$ADMIN_TOKEN" "sub")"
    record_pass "admin token provided by TODO_TEST_ADMIN_TOKEN"
    return 0
  fi
  local body file role admin_status
  body=$(cat <<JSON
{
  "username_or_email": "$ADMIN_USERNAME",
  "password": "$ADMIN_PASSWORD",
  "device_id": "todo-full-admin-$RUN_ID"
}
JSON
)
  auth_request "auth admin signin" "POST" "$AUTH_LOGIN_PATH" "200|401|403" "$body" ""
  file="$(last_file "auth admin signin")"
  ADMIN_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  ADMIN_USER_ID="$(json_get_any "$file" "data.user.id" "data.user.user_id" "user.id" "user.user_id" "sub")"
  role="$(json_get_any "$file" "data.user.role" "user.role" "role")"
  admin_status="$(json_get_any "$file" "data.user.admin_status" "user.admin_status" "admin_status")"
  [ "$ADMIN_USER_ID" = "" ] && ADMIN_USER_ID="$(jwt_claim "$ADMIN_TOKEN" "sub")"
  if [ "$ADMIN_TOKEN" = "" ]; then
    record_skip "admin token extracted" "admin signin failed or token unavailable"
    return 0
  fi
  record_pass "admin token extracted"
  if [ "$role" = "admin" ] && [ "$admin_status" = "approved" ]; then
    record_pass "admin token is approved admin"
  else
    record_skip "admin token is approved admin" "role=$role admin_status=$admin_status; hard-delete may return 403"
  fi
}

login_second_user() {
  if [ "$SECOND_TOKEN" != "" ]; then
    SECOND_USER_ID="$(jwt_claim "$SECOND_TOKEN" "sub")"
    record_pass "second user token provided"
    return 0
  fi
  if [ "$CREATE_SECOND_USER" != "1" ]; then
    record_skip "second user token" "TODO_TEST_CREATE_SECOND_USER is not 1"
    return 0
  fi
  signup_user "$SECOND_USERNAME" "$SECOND_EMAIL" "$SECOND_PASSWORD" "Todo Full API Second User"
  signin_user "$SECOND_USERNAME" "$SECOND_PASSWORD" "todo-full-second-$RUN_ID" "auth second user signin"
  local file
  file="$(last_file "auth second user signin")"
  SECOND_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  SECOND_USER_ID="$(json_get_any "$file" "data.user.id" "data.user.user_id" "user.id" "user.user_id" "sub")"
  [ "$SECOND_USER_ID" = "" ] && SECOND_USER_ID="$(jwt_claim "$SECOND_TOKEN" "sub")"
  [ "$SECOND_TOKEN" != "" ] && record_pass "second user token extracted" || record_skip "second user token extracted" "token unavailable"
}

system_endpoint_tests() {
  echo
  echo "${BOLD}System/public route tests${RESET}"
  todo_request "todo hello" "GET" "/hello" "200" "" ""
  assert_json_status_ok "todo hello"
  todo_request "todo health" "GET" "/health" "200|503" "" ""
  assert_health_shape "todo health"
  if [ "$(last_code "todo health")" = "200" ]; then
    assert_json_status_ok "todo health"
  else
    record_skip "todo health fully up" "health returned 503; inspect dependency details"
  fi
  todo_request "todo docs" "GET" "/docs" "200" "" ""

  if [ "$STRICT_PUBLIC_ROUTES" = "1" ]; then
    for path in "/" "/live" "/ready" "/healthy" "/openapi.json" "/v3/api-docs" "/swagger-ui/index.html" "/swagger-ui.html" "/actuator" "/actuator/health"; do
      todo_request "todo rejected route $path" "GET" "$path" "404" "" ""
    done
  fi
}


wait_admin_todo_projection() {
  # wait_admin_todo_projection <todo_id> <owner_user_id> <suffix>
  local todo_id="$1" owner_user_id="$2" suffix="$3"
  local attempts delay attempt outfile code projected_todo_id projected_user_id
  attempts="${TODO_TEST_ADMIN_PROJECTION_RETRIES:-12}"
  delay="${TODO_TEST_ADMIN_PROJECTION_DELAY_SECONDS:-5}"

  if [ "$ADMIN_SERVICE_URL" = "" ] || [ "$RUN_ADMIN_SERVICE_CHECKS" != "1" ]; then
    record_skip "admin todo projection $suffix" "admin URL not provided or disabled"
    return 0
  fi
  if [ "$ADMIN_TOKEN" = "" ]; then
    record_skip "admin todo projection $suffix" "admin token unavailable"
    return 0
  fi
  if [ "$todo_id" = "" ]; then
    record_skip "admin todo projection $suffix" "todo id unavailable"
    return 0
  fi

  outfile="$TMP_DIR/admin_todo_projection_${suffix}.json"
  attempt=1
  while [ "$attempt" -le "$attempts" ]; do
    code="$(curl -sS --connect-timeout 5 --max-time "$TIMEOUT" \
      -o "$outfile" -w "%{http_code}" \
      -H "accept: application/json" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "X-Request-ID: req-$(new_uuid | tr -d '-')" \
      -H "X-Trace-ID: trace-$(new_uuid | tr -d '-')" \
      -H "X-Correlation-ID: req-$(new_uuid | tr -d '-')" \
      "$ADMIN_SERVICE_URL/v1/admin/todos/$todo_id" 2>"$outfile.curlerr" || echo "000")"

    if [ "$VERBOSE" = "1" ]; then
      echo "--- admin todo projection $suffix attempt $attempt response ($code) ---"
      short_body "$outfile"
      echo "-------------------------------------------------------------"
    fi

    if [ "$code" = "200" ]; then
      projected_todo_id="$(json_get_any "$outfile" "data.todo_id" "data.todoId" "data.id" "todo_id")"
      projected_user_id="$(json_get_any "$outfile" "data.user_id" "data.userId" "user_id")"
      if [ "$projected_todo_id" = "$todo_id" ]; then
        if [ "$owner_user_id" = "" ] || [ "$projected_user_id" = "$owner_user_id" ]; then
          record_pass "admin todo projection $suffix visible in admin_service after Kafka"
          return 0
        fi
      fi
    fi

    sleep "$delay"
    attempt=$((attempt + 1))
  done

  record_fail "admin todo projection $suffix" "admin_service did not expose todo_id=$todo_id after $attempts attempts. Last HTTP=$code body=$(short_body "$outfile" | tr '\n' ' ' | cut -c1-700)"
  return 1
}

admin_service_checks() {
  echo
  echo "${BOLD}Optional admin-service checks${RESET}"
  if [ "$ADMIN_SERVICE_URL" = "" ] || [ "$RUN_ADMIN_SERVICE_CHECKS" != "1" ]; then
    record_skip "admin service checks" "admin URL not provided or disabled"
    return 0
  fi
  admin_request "admin hello" "GET" "/hello" "200" "" ""
  admin_request "admin health" "GET" "/health" "200|503" "" ""
  admin_request "admin docs" "GET" "/docs" "200" "" ""
  if [ "$ADMIN_TOKEN" != "" ]; then
    admin_request "admin dashboard with token" "GET" "/v1/admin/dashboard" "200|403|404" "" "$ADMIN_TOKEN"
  else
    record_skip "admin dashboard with token" "admin token unavailable"
  fi
}

protected_route_tests() {
  echo
  echo "${BOLD}Authentication/authorization negative tests${RESET}"
  todo_request "todos list without token" "GET" "/v1/todos" "401" "" ""
  assert_json_status_error "todos list without token" "UNAUTHORIZED|AUTHENTICATION_REQUIRED|INVALID_TOKEN"
  todo_request "todos list invalid token" "GET" "/v1/todos" "401" "" "not-a-valid-jwt"
  assert_json_status_error "todos list invalid token" "UNAUTHORIZED|AUTHENTICATION_REQUIRED|INVALID_TOKEN"
  todo_request "todos create without token" "POST" "/v1/todos" "401" '{"title":"no token"}' ""
  assert_json_status_error "todos create without token" "UNAUTHORIZED|AUTHENTICATION_REQUIRED|INVALID_TOKEN"
}

create_todo() {
  local name="$1" title="$2" priority="$3" due_date="$4" token="$5" body
  body=$(cat <<JSON
{
  "title": "$title",
  "description": "Created by todo_list_service_api_full_retry_test.sh run $RUN_ID",
  "priority": "$priority",
  "due_date": "$due_date",
  "tags": ["smoke", "todo-service", "$RUN_ID"]
}
JSON
)
  todo_request "$name" "POST" "/v1/todos" "200|201" "$body" "$token"
}

run_iteration() {
  local n="$1"
  local suffix="iter${n}-${RUN_ID}"
  local due_future due_today due_past due_after due_before primary_id today_id overdue_id hard_id body code
  due_future="$(iso_utc_hours 48)"
  due_today="$(iso_utc_hours 2)"
  due_past="$(iso_utc_hours -24)"
  due_after="$(iso_utc_date -2)T00:00:00Z"
  due_before="$(iso_utc_date 7)T23:59:59Z"

  echo
  echo "${BOLD}Todo API iteration $n of $ITERATIONS${RESET}"

  create_todo "create primary todo $suffix" "Smoke primary todo $suffix" "HIGH" "$due_future" "$ACCESS_TOKEN"
  assert_json_status_ok "create primary todo $suffix"
  primary_id="$(extract_todo_id "create primary todo $suffix")"
  if [ "$primary_id" = "" ]; then
    record_fail "primary todo id extracted $suffix" "Could not find todo id in create response"
    return 0
  fi
  record_pass "primary todo id extracted $suffix: $primary_id"
  LAST_TODO_ID="$primary_id"
  wait_admin_todo_projection "$primary_id" "$USER_ID" "$suffix"

  create_todo "create today todo $suffix" "Smoke today todo $suffix" "MEDIUM" "$due_today" "$ACCESS_TOKEN"
  assert_json_status_ok "create today todo $suffix"
  today_id="$(extract_todo_id "create today todo $suffix")"

  create_todo "create overdue todo $suffix" "Smoke overdue todo $suffix" "URGENT" "$due_past" "$ACCESS_TOKEN"
  assert_json_status_ok "create overdue todo $suffix"
  overdue_id="$(extract_todo_id "create overdue todo $suffix")"

  # Create validation failures
  todo_request "create todo missing title $suffix" "POST" "/v1/todos" "400|422" '{"description":"missing title"}' "$ACCESS_TOKEN"
  todo_request "create todo invalid priority $suffix" "POST" "/v1/todos" "400|422" '{"title":"invalid priority","priority":"BAD"}' "$ACCESS_TOKEN"
  todo_request "create todo malformed json $suffix" "POST" "/v1/todos" "400" '{"title":' "$ACCESS_TOKEN"

  # List/search/filter APIs
  todo_request "list todos $suffix" "GET" "/v1/todos?page=0&size=20" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "list todos $suffix"
  todo_request "list todos status priority $suffix" "GET" "/v1/todos?status=PENDING&priority=HIGH&page=0&size=20" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "list todos status priority $suffix"
  todo_request "list todos tag $suffix" "GET" "/v1/todos?tag=smoke&page=0&size=20" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "list todos tag $suffix"
  todo_request "list todos search $suffix" "GET" "/v1/todos?search=Smoke&page=0&size=20" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "list todos search $suffix"
  todo_request "list todos due range $suffix" "GET" "/v1/todos?due_after=$due_after&due_before=$due_before&page=0&size=20" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "list todos due range $suffix"
  todo_request "list todos include deleted $suffix" "GET" "/v1/todos?include_deleted=true&page=0&size=20" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "list todos include deleted $suffix"
  todo_request "list today todos $suffix" "GET" "/v1/todos/today" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "list today todos $suffix"
  todo_request "list overdue todos $suffix" "GET" "/v1/todos/overdue" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "list overdue todos $suffix"

  # Read/update/status APIs
  todo_request "get primary todo $suffix" "GET" "/v1/todos/$primary_id" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "get primary todo $suffix"
  todo_request "get fake todo $suffix" "GET" "/v1/todos/00000000-0000-0000-0000-000000000000" "404|400" "" "$ACCESS_TOKEN"

  body=$(cat <<JSON
{
  "title": "Smoke primary todo updated $suffix",
  "description": "Updated by full retry test run $RUN_ID iteration $n",
  "priority": "URGENT",
  "due_date": "$due_future",
  "tags": ["smoke", "updated", "$RUN_ID"]
}
JSON
)
  todo_request "update primary todo $suffix" "PUT" "/v1/todos/$primary_id" "200" "$body" "$ACCESS_TOKEN"
  assert_json_status_ok "update primary todo $suffix"
  todo_request "update todo invalid priority $suffix" "PUT" "/v1/todos/$primary_id" "400|422" '{"priority":"NOPE"}' "$ACCESS_TOKEN"

  todo_request "change todo status in progress $suffix" "PATCH" "/v1/todos/$primary_id/status" "200" '{"status":"IN_PROGRESS"}' "$ACCESS_TOKEN"
  assert_json_status_ok "change todo status in progress $suffix"
  todo_request "change todo status invalid enum $suffix" "PATCH" "/v1/todos/$primary_id/status" "400|409|422" '{"status":"NOT_A_REAL_STATUS"}' "$ACCESS_TOKEN"
  assert_json_status_error "change todo status invalid enum $suffix" "VALIDATION_ERROR|BAD_REQUEST|TODO_INVALID_STATUS|TODO_INVALID_STATUS_TRANSITION"
  todo_request "change todo status invalid transition $suffix" "PATCH" "/v1/todos/$primary_id/status" "400|409|422" '{"status":"PENDING"}' "$ACCESS_TOKEN"

  todo_request "complete primary todo $suffix" "POST" "/v1/todos/$primary_id/complete" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "complete primary todo $suffix"
  todo_request "primary todo history $suffix" "GET" "/v1/todos/$primary_id/history" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "primary todo history $suffix"
  todo_request "archive primary todo $suffix" "POST" "/v1/todos/$primary_id/archive" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "archive primary todo $suffix"
  todo_request "list archived todos $suffix" "GET" "/v1/todos?archived=true&page=0&size=20" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "list archived todos $suffix"
  todo_request "restore archived todo $suffix" "POST" "/v1/todos/$primary_id/restore" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "restore archived todo $suffix"
  todo_request "soft delete primary todo $suffix" "DELETE" "/v1/todos/$primary_id" "200|204" "" "$ACCESS_TOKEN"
  code="$(last_code "soft delete primary todo $suffix")"
  [ "$code" = "204" ] && record_pass "soft delete primary todo $suffix returned 204" || assert_json_status_ok "soft delete primary todo $suffix"
  todo_request "restore soft deleted todo $suffix" "POST" "/v1/todos/$primary_id/restore" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "restore soft deleted todo $suffix"

  # Unsupported method checks using valid resource ids.
  todo_request "unsupported post history $suffix" "POST" "/v1/todos/$primary_id/history" "404|405" "" "$ACCESS_TOKEN"
  todo_request "unsupported put complete $suffix" "PUT" "/v1/todos/$primary_id/complete" "404|405" "" "$ACCESS_TOKEN"
  todo_request "unsupported delete collection $suffix" "DELETE" "/v1/todos" "404|405" "" "$ACCESS_TOKEN"

  # Cross-user isolation
  if [ "$SECOND_TOKEN" != "" ]; then
    todo_request "second user cannot read primary todo $suffix" "GET" "/v1/todos/$primary_id" "403|404" "" "$SECOND_TOKEN"
  else
    record_skip "second user cannot read primary todo $suffix" "second token unavailable"
  fi

  # Hard delete checks
  todo_request "normal user hard delete forbidden $suffix" "DELETE" "/v1/todos/$primary_id/hard" "403" "" "$ACCESS_TOKEN"
  assert_json_status_error "normal user hard delete forbidden $suffix" "FORBIDDEN|ACCESS_DENIED|TODO_FORBIDDEN|INSUFFICIENT_PERMISSIONS"

  if [ "$ADMIN_HARD_DELETE" = "1" ] && [ "$ADMIN_TOKEN" != "" ]; then
    create_todo "create admin hard delete target $suffix" "Smoke admin hard delete target $suffix" "LOW" "$due_future" "$ACCESS_TOKEN"
    hard_id="$(extract_todo_id "create admin hard delete target $suffix")"
    if [ "$hard_id" != "" ]; then
      todo_request "admin hard delete todo $suffix" "DELETE" "/v1/todos/$hard_id/hard" "200|204|403" "" "$ADMIN_TOKEN"
      code="$(last_code "admin hard delete todo $suffix")"
      if [ "$code" = "200" ]; then
        assert_json_status_ok "admin hard delete todo $suffix"
      elif [ "$code" = "204" ]; then
        record_pass "admin hard delete todo $suffix returned 204"
      else
        record_skip "admin hard delete todo $suffix" "Todo returned 403; admin token may not be approved/admin in JWT"
      fi
    else
      record_skip "admin hard delete todo $suffix" "could not create target"
    fi
  else
    record_skip "admin hard delete todo $suffix" "admin token unavailable or disabled"
  fi

  # Cleanup remaining created todos. Non-fatal.
  for id in "$primary_id" "$today_id" "$overdue_id"; do
    if [ "$id" != "" ]; then
      todo_request "cleanup soft delete $suffix $id" "DELETE" "/v1/todos/$id" "200|204|404" "" "$ACCESS_TOKEN" >/dev/null 2>&1 || true
    fi
  done
}

print_header
wait_for_todo || true
system_endpoint_tests
login_primary_user
login_admin_token
login_second_user
admin_service_checks
protected_route_tests

if [ "$ACCESS_TOKEN" = "" ]; then
  record_fail "Todo API CRUD flow" "primary user token unavailable"
else
  for i in $(seq 1 "$ITERATIONS"); do
    run_iteration "$i"
  done
fi

echo
printf "%sSummary:%s %s total, %s passed, %s failed, %s skipped\n" "$BOLD" "$RESET" "$TEST_COUNT" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
echo "Todo Base URL:  $TODO_SERVICE_URL"
echo "Auth Base URL:  $AUTH_SERVICE_URL"
[ "$ADMIN_SERVICE_URL" != "" ] && echo "Admin Base URL: $ADMIN_SERVICE_URL"
[ "$SAVE_RESPONSES" = "1" ] && echo "Responses kept at: $TMP_DIR"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
