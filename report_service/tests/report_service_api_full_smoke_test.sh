#!/usr/bin/env bash
# Report Service full API smoke/contract test script.
#
# Purpose:
#   Test report_service public routes, protected routes, response envelopes,
#   all report APIs, and the main HTTP response codes documented in Swagger:
#   200, 201, 400, 401, 403, 404, 409.
#
# Named parameter usage:
#   chmod +x report_service_api_full_smoke_test.sh
#   ./report_service_api_full_smoke_test.sh \
#     --report-host 192.168.56.100 --report-port 5050 \
#     --auth-host 192.168.56.100 --auth-port 6060 \
#     --calculator-host 192.168.56.100 --calculator-port 2020 \
#     --todo-host 192.168.56.100 --todo-port 3030 \
#     --admin-host 192.168.56.100 --admin-port 1010
#
# URL usage:
#   ./report_service_api_full_smoke_test.sh \
#     --report-url http://3.108.225.164:5050 \
#     --auth-url http://3.108.225.164:6060 \
#     --calculator-url http://3.108.225.164:2020 \
#     --todo-url http://3.108.225.164:3030 \
#     --admin-url http://3.108.225.164:1010
#
# Environment variables:
#   REPORT_TEST_ACCESS_TOKEN=<preissued-normal-user-jwt>
#   REPORT_TEST_ADMIN_TOKEN=<preissued-admin-jwt>
#   REPORT_TEST_SECOND_TOKEN=<preissued-other-user-jwt>
#   REPORT_TEST_USERNAME=<existing-or-created-user>
#   REPORT_TEST_PASSWORD=<password>
#   REPORT_TEST_CREATE_USER=1
#   REPORT_TEST_CREATE_SECOND_USER=1
#   REPORT_TEST_ADMIN_USERNAME=admin
#   REPORT_TEST_ADMIN_PASSWORD=admin123
#   REPORT_TEST_AUTH_LOGIN_PATH=/v1/signin
#   REPORT_TEST_TIMEOUT=20
#   REPORT_TEST_RETRIES=3
#   REPORT_TEST_RETRY_DELAY_SECONDS=2
#   REPORT_TEST_VERBOSE=0
#   REPORT_TEST_SAVE_RESPONSES=0
#   REPORT_TEST_SEED_CALCULATOR=1
#   REPORT_TEST_SEED_TODO=1
#   REPORT_TEST_WAIT_COMPLETED=1
#   REPORT_TEST_COMPLETION_RETRIES=24
#   REPORT_TEST_COMPLETION_DELAY_SECONDS=5
#   REPORT_TEST_STRICT_PUBLIC_ROUTES=1
#   REPORT_TEST_REQUIRED_CODE_COVERAGE=1
#
# Exit codes:
#   0 = all required checks passed
#   1 = one or more required checks failed
#   2 = invalid script usage or missing required local command

set -u

usage() {
  cat <<'USAGE'
Usage:
  ./report_service_api_full_smoke_test.sh \
    --report-host <ip> [--report-port 5050] \
    --auth-host <ip> [--auth-port 6060] \
    [--calculator-host <ip> --calculator-port 2020] \
    [--todo-host <ip> --todo-port 3030] \
    [--admin-host <ip> --admin-port 1010]

  ./report_service_api_full_smoke_test.sh \
    --report-url http://<ip>:5050 \
    --auth-url http://<ip>:6060 \
    [--calculator-url http://<ip>:2020] \
    [--todo-url http://<ip>:3030] \
    [--admin-url http://<ip>:1010]

Named parameters:
  --report-host <host>                Report service host/IP
  --report-port <port>                Report service host port, default 5050
  --report-url <url>                  Report service base URL
  --auth-host <host>                  Auth service host/IP
  --auth-port <port>                  Auth service host port, default 6060
  --auth-url <url>                    Auth service base URL
  --calculator-host <host>            Calculator service host/IP, optional
  --calculator-port <port>            Calculator service host port, default 2020
  --calculator-url <url>              Calculator service base URL, optional
  --todo-host <host>                  Todo service host/IP, optional
  --todo-port <port>                  Todo service host port, default 3030
  --todo-url <url>                    Todo service base URL, optional
  --admin-host <host>                 Admin service host/IP, optional
  --admin-port <port>                 Admin service host port, default 1010
  --admin-url <url>                   Admin service base URL, optional
  --timeout <seconds>                 Curl max-time timeout, default 20
  --retries <n>                       Retry each HTTP request n times, default 3
  --retry-delay-seconds <n>           Delay between retries, default 2
  --verbose                           Print redacted response bodies
  --save-responses                    Keep response files in a temp directory
  --no-seed-calculator                Do not create calculator data
  --no-seed-todo                      Do not create todo data
  --no-wait-completed                 Do not wait for generated reports
  -h, --help                          Show this help
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

REPORT_SERVICE_HOST="${REPORT_SERVICE_HOST:-}"
REPORT_SERVICE_PORT="${REPORT_SERVICE_PORT:-5050}"
REPORT_SERVICE_URL="${REPORT_SERVICE_URL:-}"
AUTH_SERVICE_HOST="${AUTH_SERVICE_HOST:-}"
AUTH_SERVICE_PORT="${AUTH_SERVICE_PORT:-6060}"
AUTH_SERVICE_URL="${AUTH_SERVICE_URL:-}"
CALCULATOR_SERVICE_HOST="${CALCULATOR_SERVICE_HOST:-}"
CALCULATOR_SERVICE_PORT="${CALCULATOR_SERVICE_PORT:-2020}"
CALCULATOR_SERVICE_URL="${CALCULATOR_SERVICE_URL:-}"
TODO_SERVICE_HOST="${TODO_SERVICE_HOST:-}"
TODO_SERVICE_PORT="${TODO_SERVICE_PORT:-3030}"
TODO_SERVICE_URL="${TODO_SERVICE_URL:-}"
ADMIN_SERVICE_HOST="${ADMIN_SERVICE_HOST:-}"
ADMIN_SERVICE_PORT="${ADMIN_SERVICE_PORT:-1010}"
ADMIN_SERVICE_URL="${ADMIN_SERVICE_URL:-}"

TIMEOUT="${REPORT_TEST_TIMEOUT:-20}"
REQUEST_RETRIES="${REPORT_TEST_RETRIES:-3}"
RETRY_DELAY_SECONDS="${REPORT_TEST_RETRY_DELAY_SECONDS:-2}"
VERBOSE="${REPORT_TEST_VERBOSE:-0}"
SAVE_RESPONSES="${REPORT_TEST_SAVE_RESPONSES:-0}"
AUTH_LOGIN_PATH="${REPORT_TEST_AUTH_LOGIN_PATH:-/v1/signin}"
CREATE_USER="${REPORT_TEST_CREATE_USER:-1}"
CREATE_SECOND_USER="${REPORT_TEST_CREATE_SECOND_USER:-1}"
SEED_CALCULATOR="${REPORT_TEST_SEED_CALCULATOR:-1}"
SEED_TODO="${REPORT_TEST_SEED_TODO:-1}"
WAIT_COMPLETED="${REPORT_TEST_WAIT_COMPLETED:-1}"
COMPLETION_RETRIES="${REPORT_TEST_COMPLETION_RETRIES:-24}"
COMPLETION_DELAY_SECONDS="${REPORT_TEST_COMPLETION_DELAY_SECONDS:-5}"
STRICT_PUBLIC_ROUTES="${REPORT_TEST_STRICT_PUBLIC_ROUTES:-1}"
REQUIRED_CODE_COVERAGE="${REPORT_TEST_REQUIRED_CODE_COVERAGE:-1}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --report-host) REPORT_SERVICE_HOST="${2:-}"; shift 2 ;;
    --report-port) REPORT_SERVICE_PORT="${2:-5050}"; shift 2 ;;
    --report-url) REPORT_SERVICE_URL="${2:-}"; shift 2 ;;
    --auth-host) AUTH_SERVICE_HOST="${2:-}"; shift 2 ;;
    --auth-port) AUTH_SERVICE_PORT="${2:-6060}"; shift 2 ;;
    --auth-url) AUTH_SERVICE_URL="${2:-}"; shift 2 ;;
    --calculator-host) CALCULATOR_SERVICE_HOST="${2:-}"; shift 2 ;;
    --calculator-port) CALCULATOR_SERVICE_PORT="${2:-2020}"; shift 2 ;;
    --calculator-url) CALCULATOR_SERVICE_URL="${2:-}"; shift 2 ;;
    --todo-host) TODO_SERVICE_HOST="${2:-}"; shift 2 ;;
    --todo-port) TODO_SERVICE_PORT="${2:-3030}"; shift 2 ;;
    --todo-url) TODO_SERVICE_URL="${2:-}"; shift 2 ;;
    --admin-host) ADMIN_SERVICE_HOST="${2:-}"; shift 2 ;;
    --admin-port) ADMIN_SERVICE_PORT="${2:-1010}"; shift 2 ;;
    --admin-url) ADMIN_SERVICE_URL="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-20}"; shift 2 ;;
    --retries) REQUEST_RETRIES="${2:-3}"; shift 2 ;;
    --retry-delay-seconds) RETRY_DELAY_SECONDS="${2:-2}"; shift 2 ;;
    --verbose) VERBOSE=1; shift 1 ;;
    --save-responses) SAVE_RESPONSES=1; shift 1 ;;
    --no-seed-calculator) SEED_CALCULATOR=0; shift 1 ;;
    --no-seed-todo) SEED_TODO=0; shift 1 ;;
    --no-wait-completed) WAIT_COMPLETED=0; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

if [ -z "$REPORT_SERVICE_URL" ]; then REPORT_SERVICE_URL="$(normalize_base_url "$REPORT_SERVICE_HOST" "$REPORT_SERVICE_PORT")"; fi
if [ -z "$AUTH_SERVICE_URL" ]; then AUTH_SERVICE_URL="$(normalize_base_url "$AUTH_SERVICE_HOST" "$AUTH_SERVICE_PORT")"; fi
if [ -z "$CALCULATOR_SERVICE_URL" ]; then CALCULATOR_SERVICE_URL="$(normalize_base_url "$CALCULATOR_SERVICE_HOST" "$CALCULATOR_SERVICE_PORT")"; fi
if [ -z "$TODO_SERVICE_URL" ]; then TODO_SERVICE_URL="$(normalize_base_url "$TODO_SERVICE_HOST" "$TODO_SERVICE_PORT")"; fi
if [ -z "$ADMIN_SERVICE_URL" ]; then ADMIN_SERVICE_URL="$(normalize_base_url "$ADMIN_SERVICE_HOST" "$ADMIN_SERVICE_PORT")"; fi

if [ -z "$REPORT_SERVICE_URL" ] || [ -z "$AUTH_SERVICE_URL" ]; then
  echo "Missing required Report/Auth service input. Use --report-host/--auth-host or --report-url/--auth-url."
  usage
  exit 2
fi

case "$REQUEST_RETRIES" in ''|*[!0-9]*) echo "--retries must be a positive integer"; exit 2 ;; esac
case "$RETRY_DELAY_SECONDS" in ''|*[!0-9]*) echo "--retry-delay-seconds must be a non-negative integer"; exit 2 ;; esac
case "$COMPLETION_RETRIES" in ''|*[!0-9]*) echo "REPORT_TEST_COMPLETION_RETRIES must be a positive integer"; exit 2 ;; esac
case "$COMPLETION_DELAY_SECONDS" in ''|*[!0-9]*) echo "REPORT_TEST_COMPLETION_DELAY_SECONDS must be a non-negative integer"; exit 2 ;; esac
[ "$REQUEST_RETRIES" -lt 1 ] && REQUEST_RETRIES=1
[ "$COMPLETION_RETRIES" -lt 1 ] && COMPLETION_RETRIES=1

ADMIN_USERNAME="${REPORT_TEST_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${REPORT_TEST_ADMIN_PASSWORD:-admin123}"
ACCESS_TOKEN="${REPORT_TEST_ACCESS_TOKEN:-}"
ADMIN_TOKEN="${REPORT_TEST_ADMIN_TOKEN:-}"
SECOND_TOKEN="${REPORT_TEST_SECOND_TOKEN:-}"

RUN_ID="$(date +%s)-$RANDOM"
TEST_USERNAME="${REPORT_TEST_USERNAME:-reportuser_${RUN_ID}}"
TEST_EMAIL="${TEST_USERNAME}@example.com"
TEST_PASSWORD="${REPORT_TEST_PASSWORD:-Test1234!Aa}"
SECOND_USERNAME="reportother_${RUN_ID}"
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
CREATED_REPORT_ID=""
CONFLICT_REPORT_ID=""
COMPLETED_REPORT_ID=""
TEMPLATE_ID=""
SCHEDULE_ID=""
AUDIT_EVENT_ID=""
OBSERVED_CODES=""

if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
  GREEN="$(tput setaf 2)"; RED="$(tput setaf 1)"; YELLOW="$(tput setaf 3)"; BLUE="$(tput setaf 4)"; BOLD="$(tput bold)"; RESET="$(tput sgr0)"
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

new_uuid() { python3 - <<'PY'
import uuid
print(str(uuid.uuid4()))
PY
}

safe_name() { printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_'; }

iso_utc_hours() {
  python3 - "$1" <<'PY'
from datetime import datetime, timezone, timedelta
import sys
hours = int(sys.argv[1])
print((datetime.now(timezone.utc) + timedelta(hours=hours)).replace(microsecond=0).isoformat().replace('+00:00', 'Z'))
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

jwt_claim() {
  python3 - "$1" "$2" <<'PY'
import base64, json, sys
jwt, claim = sys.argv[1], sys.argv[2]
try:
    payload = jwt.split('.')[1]
    payload += '=' * (-len(payload) % 4)
    obj = json.loads(base64.urlsafe_b64decode(payload.encode()).decode())
    val = obj.get(claim, '')
    print(json.dumps(val, separators=(',', ':')) if isinstance(val, (dict, list)) else val)
except Exception:
    print('')
PY
}

json_status() { json_get "$1" "status"; }

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
        print(json.dumps(redact(obj), indent=2)[:1800])
    except Exception:
        print(data[:1800])
except Exception as exc:
    print(f'<unable to read response: {exc}>')
PY
}

record_pass() { TEST_COUNT=$((TEST_COUNT + 1)); PASS_COUNT=$((PASS_COUNT + 1)); printf "%s[PASS]%s %s\n" "$GREEN" "$RESET" "$1"; }
record_fail() { TEST_COUNT=$((TEST_COUNT + 1)); FAIL_COUNT=$((FAIL_COUNT + 1)); printf "%s[FAIL]%s %s\n" "$RED" "$RESET" "$1"; [ "${2:-}" != "" ] && echo "       $2"; }
record_skip() { TEST_COUNT=$((TEST_COUNT + 1)); SKIP_COUNT=$((SKIP_COUNT + 1)); printf "%s[SKIP]%s %s\n" "$YELLOW" "$RESET" "$1"; [ "${2:-}" != "" ] && echo "       $2"; }

last_file() { cat "$TMP_DIR/$(safe_name "$1").path" 2>/dev/null || true; }
last_code() { cat "$TMP_DIR/$(safe_name "$1").code" 2>/dev/null || true; }

remember_code() {
  case " $OBSERVED_CODES " in *" $1 "*) ;; *) OBSERVED_CODES="$OBSERVED_CODES $1" ;; esac
}

is_retryable_code() {
  case "$1" in 000|408|425|429|500|502|503|504) return 0 ;; *) return 1 ;; esac
}

request_base() {
  # request_base <base_url> <name> <method> <path> <expected_codes_regex> <body_or_empty> <bearer_token_or_empty>
  local base_url="$1" name="$2" method="$3" path="$4" expected="$5" body="${6:-}" token="${7:-}"
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
    if [ "$token" != "" ]; then curl_args+=( -H "Authorization: Bearer $token" ); fi
    if [ "$body" != "" ]; then curl_args+=( -H "Content-Type: application/json" -d "$body" ); fi

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
      remember_code "$http_code"
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

  [ "$curl_exit" -eq 0 ] && remember_code "$http_code"
  response_summary="$(short_body "$outfile" | tr '\n' ' ' | cut -c1-1100)"
  if [ "$curl_exit" -ne 0 ]; then
    record_fail "$name ($method $path curl failed after $attempt attempt(s))" "$(cat "$outfile.curlerr" 2>/dev/null)"
  else
    record_fail "$name ($method $path expected HTTP $expected but got $http_code after $attempt attempt(s))" "response: $response_summary"
  fi
  return 1
}

report_request() { request_base "$REPORT_SERVICE_URL" "$@"; }
auth_request() { request_base "$AUTH_SERVICE_URL" "$@"; }
calc_request() { request_base "$CALCULATOR_SERVICE_URL" "$@"; }
todo_request() { request_base "$TODO_SERVICE_URL" "$@"; }
admin_request() { request_base "$ADMIN_SERVICE_URL" "$@"; }

assert_json_status_ok() {
  local name="$1" file status
  file="$(last_file "$name")"
  status="$(json_status "$file")"
  if [ "$status" = "ok" ]; then
    record_pass "$name envelope status is ok"
  else
    record_fail "$name envelope status" "expected status=ok, got '$status'. Body: $(short_body "$file" | tr '\n' ' ' | cut -c1-800)"
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
    record_fail "$name error envelope" "expected status=error and error_code=$expected_error, got status=$status error_code=$error_code. Body: $(short_body "$file" | tr '\n' ' ' | cut -c1-800)"
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
  if [ "$rc" -eq 0 ]; then record_pass "$name health dependency shape"; else record_fail "$name health dependency shape" "$(short_body "$file" | tr '\n' ' ' | cut -c1-800)"; fi
}

assert_report_id_from() {
  local name="$1" file id
  file="$(last_file "$name")"
  id="$(json_get_any "$file" "data.report_id" "data.report.report_id" "report_id")"
  if [ "$id" != "" ]; then
    printf '%s' "$id"
    return 0
  fi
  return 1
}

print_header() {
  echo "${BOLD}${BLUE}Report Service Full API Smoke Test${RESET}"
  echo "Report Base URL:     $REPORT_SERVICE_URL"
  echo "Auth Base URL:       $AUTH_SERVICE_URL"
  echo "Calculator Base URL: ${CALCULATOR_SERVICE_URL:-<not provided>}"
  echo "Todo Base URL:       ${TODO_SERVICE_URL:-<not provided>}"
  echo "Admin Base URL:      ${ADMIN_SERVICE_URL:-<not provided>}"
  echo "Auth Login Path:     $AUTH_LOGIN_PATH"
  echo "Retries/request:     $REQUEST_RETRIES"
  echo "Timeout seconds:     $TIMEOUT"
  echo "Run ID:              $RUN_ID"
  echo
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
    record_pass "primary user token provided by REPORT_TEST_ACCESS_TOKEN"
    [ "$USER_ID" != "" ] && record_pass "primary user id extracted from JWT: $USER_ID" || record_skip "primary user id extracted" "JWT sub unavailable"
    return 0
  fi
  if [ "$CREATE_USER" = "1" ]; then signup_user "$TEST_USERNAME" "$TEST_EMAIL" "$TEST_PASSWORD" "Report API Test User"; fi
  signin_user "$TEST_USERNAME" "$TEST_PASSWORD" "report-smoke-$RUN_ID" "auth primary user signin"
  local file role
  file="$(last_file "auth primary user signin")"
  ACCESS_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  USER_ID="$(json_get_any "$file" "data.user.id" "data.user.user_id" "user.id" "user.user_id" "sub")"
  [ "$USER_ID" = "" ] && USER_ID="$(jwt_claim "$ACCESS_TOKEN" "sub")"
  role="$(json_get_any "$file" "data.user.role" "user.role" "role")"
  [ "$ACCESS_TOKEN" != "" ] && record_pass "primary user access token extracted" || record_fail "primary user access token extracted" "No token found."
  [ "$USER_ID" != "" ] && record_pass "primary user id extracted: $USER_ID" || record_fail "primary user id extracted" "No user id found."
  [ "$role" = "user" ] && record_pass "primary user role is user" || record_skip "primary user role is user" "role=$role"
}

login_second_user() {
  if [ "$SECOND_TOKEN" != "" ]; then
    SECOND_USER_ID="$(jwt_claim "$SECOND_TOKEN" "sub")"
    record_pass "second user token provided by REPORT_TEST_SECOND_TOKEN"
    return 0
  fi
  if [ "$CREATE_SECOND_USER" != "1" ]; then record_skip "second user token" "REPORT_TEST_CREATE_SECOND_USER is not 1"; return 0; fi
  signup_user "$SECOND_USERNAME" "$SECOND_EMAIL" "$SECOND_PASSWORD" "Report API Second User"
  signin_user "$SECOND_USERNAME" "$SECOND_PASSWORD" "report-smoke-second-$RUN_ID" "auth second user signin"
  local file
  file="$(last_file "auth second user signin")"
  SECOND_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  SECOND_USER_ID="$(json_get_any "$file" "data.user.id" "data.user.user_id" "user.id" "user.user_id" "sub")"
  [ "$SECOND_USER_ID" = "" ] && SECOND_USER_ID="$(jwt_claim "$SECOND_TOKEN" "sub")"
  [ "$SECOND_TOKEN" != "" ] && record_pass "second user token extracted" || record_skip "second user token extracted" "token unavailable"
  [ "$SECOND_USER_ID" != "" ] && record_pass "second user id extracted: $SECOND_USER_ID" || record_skip "second user id extracted" "not present"
}

login_admin_token() {
  if [ "$ADMIN_TOKEN" != "" ]; then
    ADMIN_USER_ID="$(jwt_claim "$ADMIN_TOKEN" "sub")"
    record_pass "admin token provided by REPORT_TEST_ADMIN_TOKEN"
    return 0
  fi
  local body file role admin_status
  body=$(cat <<JSON
{
  "username_or_email": "$ADMIN_USERNAME",
  "password": "$ADMIN_PASSWORD",
  "device_id": "report-smoke-admin-$RUN_ID"
}
JSON
)
  auth_request "auth admin signin" "POST" "$AUTH_LOGIN_PATH" "200|401|403" "$body" ""
  file="$(last_file "auth admin signin")"
  ADMIN_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  ADMIN_USER_ID="$(json_get_any "$file" "data.user.id" "data.user.user_id" "user.id" "user.user_id" "sub")"
  [ "$ADMIN_USER_ID" = "" ] && ADMIN_USER_ID="$(jwt_claim "$ADMIN_TOKEN" "sub")"
  role="$(json_get_any "$file" "data.user.role" "user.role" "role")"
  admin_status="$(json_get_any "$file" "data.user.admin_status" "user.admin_status" "admin_status")"
  if [ "$ADMIN_TOKEN" = "" ]; then record_skip "admin token extracted" "admin signin failed or token unavailable"; return 0; fi
  record_pass "admin token extracted"
  if [ "$role" = "admin" ] && [ "$admin_status" = "approved" ]; then
    record_pass "admin token is approved admin"
  else
    record_skip "admin token is approved admin" "role=$role admin_status=$admin_status; management checks may return 403"
  fi
}

seed_calculator_data() {
  if [ "$SEED_CALCULATOR" != "1" ] || [ "$CALCULATOR_SERVICE_URL" = "" ]; then record_skip "calculator seed" "calculator URL not provided or disabled"; return 0; fi
  calc_request "calculator seed hello" "GET" "/hello" "200" "" ""
  calc_request "calculator seed add" "POST" "/v1/calculator/calculate" "200" '{"operation":"ADD","operands":[10,20,5]}' "$ACCESS_TOKEN"
  calc_request "calculator seed expression" "POST" "/v1/calculator/calculate" "200" '{"expression":"sqrt(16)+(10+5)*3"}' "$ACCESS_TOKEN"
}

seed_todo_data() {
  if [ "$SEED_TODO" != "1" ] || [ "$TODO_SERVICE_URL" = "" ]; then record_skip "todo seed" "todo URL not provided or disabled"; return 0; fi
  local due body todo_id file
  due="$(iso_utc_hours 48)"
  todo_request "todo seed hello" "GET" "/hello" "200" "" ""
  body=$(cat <<JSON
{
  "title": "Report service smoke seed todo $RUN_ID",
  "description": "Seed todo for report_service projection tests",
  "priority": "HIGH",
  "due_date": "$due",
  "tags": ["report-service", "smoke", "$RUN_ID"]
}
JSON
)
  todo_request "todo seed create" "POST" "/v1/todos" "200|201" "$body" "$ACCESS_TOKEN"
  file="$(last_file "todo seed create")"
  todo_id="$(json_get_any "$file" "data.id" "data.todo.id" "data.todo.todo_id" "data.todo_id" "id" "todo_id")"
  if [ "$todo_id" != "" ]; then
    todo_request "todo seed complete" "POST" "/v1/todos/$todo_id/complete" "200|404|409" "" "$ACCESS_TOKEN"
  else
    record_skip "todo seed complete" "todo id not returned"
  fi
}

system_endpoint_tests() {
  echo
  echo "${BOLD}System/public route tests${RESET}"
  report_request "report hello" "GET" "/hello" "200" "" ""
  assert_json_status_ok "report hello"
  report_request "report health" "GET" "/health" "200|503" "" ""
  assert_health_shape "report health"
  if [ "$(last_code "report health")" = "200" ]; then assert_json_status_ok "report health"; else record_skip "report health fully up" "health returned 503; inspect dependency details"; fi
  report_request "report docs" "GET" "/docs" "200" "" ""
  if [ "$STRICT_PUBLIC_ROUTES" = "1" ]; then
    for path in "/" "/live" "/ready" "/healthy" "/openapi.json" "/v3/api-docs" "/swagger" "/swagger-ui" "/swagger-ui/index.html" "/documentation/json" "/redoc" "/actuator" "/actuator/health" "/metrics" "/debug" "/admin"; do
      report_request "report rejected route $path" "GET" "$path" "404" "" ""
    done
  fi
}

protected_route_tests() {
  echo
  echo "${BOLD}Authentication/authorization negative tests${RESET}"
  report_request "types without token" "GET" "/v1/reports/types" "401" "" ""
  assert_json_status_error "types without token" "UNAUTHORIZED"
  report_request "types invalid token" "GET" "/v1/reports/types" "401" "" "not-a-valid-jwt"
  assert_json_status_error "types invalid token" "UNAUTHORIZED"
  report_request "create report without token" "POST" "/v1/reports" "401" '{"report_type":"calculator_history_report"}' ""
  assert_json_status_error "create report without token" "UNAUTHORIZED"
  report_request "queue summary normal user forbidden" "GET" "/v1/reports/queue/summary" "403" "" "$ACCESS_TOKEN"
  assert_json_status_error "queue summary normal user forbidden" "FORBIDDEN"
  report_request "admin-only report type normal user forbidden" "POST" "/v1/reports" "403" '{"report_type":"admin_decision_report","format":"json","filters":{},"options":{}}' "$ACCESS_TOKEN"
  assert_json_status_error "admin-only report type normal user forbidden" "FORBIDDEN"
}

create_report() {
  local name="$1" report_type="$2" format="$3" token="$4" extra="${5:-}"
  local body
  if [ "$extra" != "" ]; then
    body="$extra"
  else
    body=$(cat <<JSON
{
  "report_type": "$report_type",
  "format": "$format",
  "date_from": "2026-05-01",
  "date_to": "2026-05-09",
  "filters": {},
  "options": {
    "include_summary": true,
    "include_charts": true,
    "include_raw_data": true,
    "timezone": "Asia/Dhaka",
    "locale": "en",
    "title": "Smoke Test $report_type $format"
  }
}
JSON
)
  fi
  report_request "$name" "POST" "/v1/reports" "201" "$body" "$token"
}

wait_for_report_completed() {
  local report_id="$1" name="$2" i file status
  if [ "$WAIT_COMPLETED" != "1" ]; then record_skip "$name completed" "REPORT_TEST_WAIT_COMPLETED is not 1"; return 0; fi
  if [ "$report_id" = "" ]; then record_skip "$name completed" "report id unavailable"; return 0; fi
  echo "Waiting for report $report_id to complete..."
  i=1
  while [ "$i" -le "$COMPLETION_RETRIES" ]; do
    report_request "$name poll status $i" "GET" "/v1/reports/$report_id" "200|404" "" "$ACCESS_TOKEN" >/dev/null 2>&1 || true
    file="$(last_file "$name poll status $i")"
    status="$(json_get "$file" "data.status")"
    if [ "$status" = "COMPLETED" ]; then
      COMPLETED_REPORT_ID="$report_id"
      record_pass "$name reached COMPLETED after $i poll(s)"
      return 0
    fi
    if [ "$status" = "FAILED" ] || [ "$status" = "CANCELLED" ] || [ "$status" = "DELETED" ]; then
      record_fail "$name completed" "terminal status=$status; body=$(short_body "$file" | tr '\n' ' ' | cut -c1-900)"
      return 1
    fi
    sleep "$COMPLETION_DELAY_SECONDS"
    i=$((i + 1))
  done
  record_skip "$name completed" "not completed after $COMPLETION_RETRIES polls; last status=$status"
  return 0
}

report_core_tests() {
  echo
  echo "${BOLD}Report type, lifecycle, and response-code tests${RESET}"
  report_request "list report types" "GET" "/v1/reports/types" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "list report types"
  report_request "get calculator history report type" "GET" "/v1/reports/types/calculator_history_report" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "get calculator history report type"
  report_request "get missing report type" "GET" "/v1/reports/types/not_a_real_report" "404" "" "$ACCESS_TOKEN"
  assert_json_status_error "get missing report type" "NOT_FOUND"

  create_report "create json report" "calculator_history_report" "json" "$ACCESS_TOKEN"
  assert_json_status_ok "create json report"
  CREATED_REPORT_ID="$(assert_report_id_from "create json report" || true)"
  [ "$CREATED_REPORT_ID" != "" ] && record_pass "created report id extracted: $CREATED_REPORT_ID" || record_fail "created report id extracted" "missing data.report_id"

  create_report "create csv report" "calculator_history_report" "csv" "$ACCESS_TOKEN"
  create_report "create html report" "todo_summary_report" "html" "$ACCESS_TOKEN"
  create_report "create pdf report" "user_activity_report" "pdf" "$ACCESS_TOKEN"
  create_report "create xlsx report" "full_user_report" "xlsx" "$ACCESS_TOKEN"

  report_request "create report unsupported type" "POST" "/v1/reports" "400" '{"report_type":"not_real","format":"json","filters":{},"options":{}}' "$ACCESS_TOKEN"
  assert_json_status_error "create report unsupported type" "VALIDATION_ERROR"
  report_request "create report bad date order" "POST" "/v1/reports" "400" '{"report_type":"calculator_history_report","format":"json","date_from":"2026-05-10","date_to":"2026-05-01","filters":{},"options":{}}' "$ACCESS_TOKEN"
  assert_json_status_error "create report bad date order" "VALIDATION_ERROR"
  report_request "create report unsupported filter" "POST" "/v1/reports" "400" '{"report_type":"calculator_history_report","format":"json","filters":{"bad_filter":"x"},"options":{}}' "$ACCESS_TOKEN"
  assert_json_status_error "create report unsupported filter" "VALIDATION_ERROR"
  report_request "create report malformed json" "POST" "/v1/reports" "400" '{"report_type":' "$ACCESS_TOKEN"

  report_request "list reports" "GET" "/v1/reports?limit=20&offset=0" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "list reports"
  report_request "list reports invalid status" "GET" "/v1/reports?status=NOPE" "400" "" "$ACCESS_TOKEN"
  assert_json_status_error "list reports invalid status" "VALIDATION_ERROR"

  if [ "$CREATED_REPORT_ID" != "" ]; then
    report_request "get created report" "GET" "/v1/reports/$CREATED_REPORT_ID" "200" "" "$ACCESS_TOKEN"
    assert_json_status_ok "get created report"
    report_request "get created report progress" "GET" "/v1/reports/$CREATED_REPORT_ID/progress" "200|404" "" "$ACCESS_TOKEN"
    report_request "get created report events" "GET" "/v1/reports/$CREATED_REPORT_ID/events" "200" "" "$ACCESS_TOKEN"
    report_request "get created report files" "GET" "/v1/reports/$CREATED_REPORT_ID/files" "200" "" "$ACCESS_TOKEN"
    report_request "get created report metadata before complete" "GET" "/v1/reports/$CREATED_REPORT_ID/metadata" "200|409" "" "$ACCESS_TOKEN"
    report_request "get created report preview before complete" "GET" "/v1/reports/$CREATED_REPORT_ID/preview" "200|409|404" "" "$ACCESS_TOKEN"
    report_request "get created report download before complete" "GET" "/v1/reports/$CREATED_REPORT_ID/download" "200|409|404" "" "$ACCESS_TOKEN"
  fi

  create_report "create conflict report" "calculator_history_report" "json" "$ACCESS_TOKEN"
  CONFLICT_REPORT_ID="$(assert_report_id_from "create conflict report" || true)"
  if [ "$CONFLICT_REPORT_ID" != "" ]; then
    report_request "retry non failed report gives conflict" "POST" "/v1/reports/$CONFLICT_REPORT_ID/retry" "409" "" "$ACCESS_TOKEN"
    assert_json_status_error "retry non failed report gives conflict" "CONFLICT"
    report_request "regenerate non failed report gives conflict" "POST" "/v1/reports/$CONFLICT_REPORT_ID/regenerate" "409" "" "$ACCESS_TOKEN"
    assert_json_status_error "regenerate non failed report gives conflict" "CONFLICT"
    report_request "cancel report" "POST" "/v1/reports/$CONFLICT_REPORT_ID/cancel" "200|409" "" "$ACCESS_TOKEN"
  fi

  local missing="missing-report-$(new_uuid)"
  report_request "get missing report" "GET" "/v1/reports/$missing" "404" "" "$ACCESS_TOKEN"
  assert_json_status_error "get missing report" "NOT_FOUND"
  report_request "cancel missing report" "POST" "/v1/reports/$missing/cancel" "404" "" "$ACCESS_TOKEN"
  report_request "retry missing report" "POST" "/v1/reports/$missing/retry" "404" "" "$ACCESS_TOKEN"
  report_request "delete missing report" "DELETE" "/v1/reports/$missing" "404" "" "$ACCESS_TOKEN"
  report_request "metadata missing report" "GET" "/v1/reports/$missing/metadata" "404" "" "$ACCESS_TOKEN"
  report_request "preview missing report" "GET" "/v1/reports/$missing/preview" "404" "" "$ACCESS_TOKEN"
  report_request "progress missing report" "GET" "/v1/reports/$missing/progress" "404" "" "$ACCESS_TOKEN"
  report_request "events missing report" "GET" "/v1/reports/$missing/events" "404" "" "$ACCESS_TOKEN"
  report_request "files missing report" "GET" "/v1/reports/$missing/files" "404" "" "$ACCESS_TOKEN"

  if [ "$SECOND_TOKEN" != "" ] && [ "$CREATED_REPORT_ID" != "" ]; then
    report_request "second user cannot read primary report" "GET" "/v1/reports/$CREATED_REPORT_ID" "403" "" "$SECOND_TOKEN"
    assert_json_status_error "second user cannot read primary report" "FORBIDDEN"
  else
    record_skip "second user cannot read primary report" "second token or report id unavailable"
  fi

  if [ "$CREATED_REPORT_ID" != "" ]; then wait_for_report_completed "$CREATED_REPORT_ID" "created report"; fi
  if [ "$COMPLETED_REPORT_ID" != "" ]; then
    report_request "completed report metadata" "GET" "/v1/reports/$COMPLETED_REPORT_ID/metadata" "200" "" "$ACCESS_TOKEN"
    assert_json_status_ok "completed report metadata"
    report_request "completed report preview" "GET" "/v1/reports/$COMPLETED_REPORT_ID/preview" "200|404" "" "$ACCESS_TOKEN"
    report_request "completed report files" "GET" "/v1/reports/$COMPLETED_REPORT_ID/files" "200" "" "$ACCESS_TOKEN"
    report_request "completed report download" "GET" "/v1/reports/$COMPLETED_REPORT_ID/download" "200" "" "$ACCESS_TOKEN"
    report_request "delete completed report" "DELETE" "/v1/reports/$COMPLETED_REPORT_ID" "200" "" "$ACCESS_TOKEN"
    assert_json_status_ok "delete completed report"
  fi
}

template_tests() {
  echo
  echo "${BOLD}Template API tests${RESET}"
  report_request "templates list normal forbidden" "GET" "/v1/reports/templates" "403" "" "$ACCESS_TOKEN"
  assert_json_status_error "templates list normal forbidden" "FORBIDDEN"
  if [ "$ADMIN_TOKEN" = "" ]; then record_skip "template admin tests" "admin token unavailable"; return 0; fi

  report_request "templates list admin" "GET" "/v1/reports/templates" "200" "" "$ADMIN_TOKEN"
  assert_json_status_ok "templates list admin"
  local body
  body=$(cat <<JSON
{
  "report_type": "calculator_history_report",
  "name": "Smoke Template $RUN_ID",
  "description": "Created by report smoke test",
  "format": "pdf",
  "template_content": "{}",
  "schema": {"visible_columns": ["operation", "status", "occurred_at"]},
  "style": {"logo_text": "Micro App", "footer_text": "Internal"}
}
JSON
)
  report_request "template create admin" "POST" "/v1/reports/templates" "201" "$body" "$ADMIN_TOKEN"
  assert_json_status_ok "template create admin"
  local file
  file="$(last_file "template create admin")"
  TEMPLATE_ID="$(json_get_any "$file" "data.template_id" "data.id" "template_id" "id")"
  [ "$TEMPLATE_ID" != "" ] && record_pass "template id extracted: $TEMPLATE_ID" || record_skip "template id extracted" "template create response did not expose id"
  report_request "template create unsupported type" "POST" "/v1/reports/templates" "400" '{"report_type":"bad_type","name":"bad"}' "$ADMIN_TOKEN"
  assert_json_status_error "template create unsupported type" "VALIDATION_ERROR"
  report_request "template create invalid body" "POST" "/v1/reports/templates" "400" '{"name":"missing report type"}' "$ADMIN_TOKEN"
  assert_json_status_error "template create invalid body" "VALIDATION_ERROR"

  local missing="missing-template-$(new_uuid)"
  report_request "template get missing" "GET" "/v1/reports/templates/$missing" "404" "" "$ADMIN_TOKEN"
  report_request "template update missing" "PUT" "/v1/reports/templates/$missing" "404" '{"name":"Nope"}' "$ADMIN_TOKEN"
  report_request "template activate missing" "POST" "/v1/reports/templates/$missing/activate" "404" "" "$ADMIN_TOKEN"
  report_request "template deactivate missing" "POST" "/v1/reports/templates/$missing/deactivate" "404" "" "$ADMIN_TOKEN"

  if [ "$TEMPLATE_ID" != "" ]; then
    report_request "template get admin" "GET" "/v1/reports/templates/$TEMPLATE_ID" "200" "" "$ADMIN_TOKEN"
    report_request "template update admin" "PUT" "/v1/reports/templates/$TEMPLATE_ID" "200" '{"name":"Smoke Template Updated"}' "$ADMIN_TOKEN"
    report_request "template activate admin" "POST" "/v1/reports/templates/$TEMPLATE_ID/activate" "200" "" "$ADMIN_TOKEN"
    report_request "template deactivate admin" "POST" "/v1/reports/templates/$TEMPLATE_ID/deactivate" "200" "" "$ADMIN_TOKEN"
  fi
}

schedule_tests() {
  echo
  echo "${BOLD}Schedule API tests${RESET}"
  report_request "schedules list" "GET" "/v1/reports/schedules" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "schedules list"
  local body
  body=$(cat <<JSON
{
  "report_type": "todo_summary_report",
  "format": "pdf",
  "cron_expression": "0 9 * * *",
  "timezone": "Asia/Dhaka",
  "filters": {},
  "options": {"include_summary": true}
}
JSON
)
  report_request "schedule create" "POST" "/v1/reports/schedules" "201" "$body" "$ACCESS_TOKEN"
  assert_json_status_ok "schedule create"
  local file
  file="$(last_file "schedule create")"
  SCHEDULE_ID="$(json_get_any "$file" "data.schedule_id" "data.id" "schedule_id" "id")"
  [ "$SCHEDULE_ID" != "" ] && record_pass "schedule id extracted: $SCHEDULE_ID" || record_skip "schedule id extracted" "schedule create response did not expose id"
  report_request "schedule create invalid body" "POST" "/v1/reports/schedules" "400" '{"report_type":"todo_summary_report"}' "$ACCESS_TOKEN"
  assert_json_status_error "schedule create invalid body" "VALIDATION_ERROR"
  report_request "schedule create unsupported type" "POST" "/v1/reports/schedules" "400" '{"report_type":"nope","cron_expression":"0 9 * * *"}' "$ACCESS_TOKEN"
  assert_json_status_error "schedule create unsupported type" "VALIDATION_ERROR"

  local missing="missing-schedule-$(new_uuid)"
  report_request "schedule get missing" "GET" "/v1/reports/schedules/$missing" "404" "" "$ACCESS_TOKEN"
  report_request "schedule update missing" "PUT" "/v1/reports/schedules/$missing" "404" '{"timezone":"UTC"}' "$ACCESS_TOKEN"
  report_request "schedule pause missing" "POST" "/v1/reports/schedules/$missing/pause" "404" "" "$ACCESS_TOKEN"
  report_request "schedule resume missing" "POST" "/v1/reports/schedules/$missing/resume" "404" "" "$ACCESS_TOKEN"
  report_request "schedule delete missing" "DELETE" "/v1/reports/schedules/$missing" "404" "" "$ACCESS_TOKEN"

  if [ "$SCHEDULE_ID" != "" ]; then
    report_request "schedule get" "GET" "/v1/reports/schedules/$SCHEDULE_ID" "200" "" "$ACCESS_TOKEN"
    report_request "schedule update" "PUT" "/v1/reports/schedules/$SCHEDULE_ID" "200" '{"timezone":"UTC"}' "$ACCESS_TOKEN"
    report_request "schedule pause" "POST" "/v1/reports/schedules/$SCHEDULE_ID/pause" "200" "" "$ACCESS_TOKEN"
    report_request "schedule resume" "POST" "/v1/reports/schedules/$SCHEDULE_ID/resume" "200" "" "$ACCESS_TOKEN"
    report_request "schedule delete" "DELETE" "/v1/reports/schedules/$SCHEDULE_ID" "200" "" "$ACCESS_TOKEN"
  fi
}

management_tests() {
  echo
  echo "${BOLD}Management/observability API tests${RESET}"
  report_request "audit list normal forbidden" "GET" "/v1/reports/audit" "403" "" "$ACCESS_TOKEN"
  assert_json_status_error "audit list normal forbidden" "FORBIDDEN"
  if [ "$ADMIN_TOKEN" = "" ]; then record_skip "management admin tests" "admin token unavailable"; return 0; fi
  report_request "queue summary admin" "GET" "/v1/reports/queue/summary" "200" "" "$ADMIN_TOKEN"
  assert_json_status_ok "queue summary admin"
  report_request "audit list admin" "GET" "/v1/reports/audit?limit=20&offset=0" "200" "" "$ADMIN_TOKEN"
  assert_json_status_ok "audit list admin"
  local file
  file="$(last_file "audit list admin")"
  AUDIT_EVENT_ID="$(json_get_any "$file" "data.audit_events.0.event_id" "data.items.0.event_id" "data.0.event_id")"
  if [ "$AUDIT_EVENT_ID" != "" ]; then
    report_request "audit get admin" "GET" "/v1/reports/audit/$AUDIT_EVENT_ID" "200" "" "$ADMIN_TOKEN"
  else
    record_skip "audit get admin" "no audit event id found"
  fi
  report_request "audit get missing admin" "GET" "/v1/reports/audit/missing-audit-$(new_uuid)" "404" "" "$ADMIN_TOKEN"
}

admin_compatibility_checks() {
  if [ "$ADMIN_SERVICE_URL" = "" ] || [ "$ADMIN_TOKEN" = "" ]; then record_skip "admin compatibility checks" "admin URL or token unavailable"; return 0; fi
  echo
  echo "${BOLD}Optional Admin service compatibility checks${RESET}"
  admin_request "admin hello" "GET" "/hello" "200" "" ""
  admin_request "admin reports list" "GET" "/v1/admin/reports" "200|403|404" "" "$ADMIN_TOKEN"
  admin_request "admin reports summary" "GET" "/v1/admin/reports/summary" "200|403|404" "" "$ADMIN_TOKEN"
  if [ "$USER_ID" != "" ]; then admin_request "admin user reports projection" "GET" "/v1/admin/reports/users/$USER_ID" "200|403|404" "" "$ADMIN_TOKEN"; fi
}

verify_response_code_coverage() {
  echo
  echo "${BOLD}Swagger response-code coverage${RESET}"
  local required="200 201 400 401 403 404 409" missing="" code
  for code in $required; do
    case " $OBSERVED_CODES " in
      *" $code "*) record_pass "observed HTTP $code" ;;
      *) missing="$missing $code"; record_fail "observed HTTP $code" "not observed in this run" ;;
    esac
  done
  if [ "$missing" != "" ] && [ "$REQUIRED_CODE_COVERAGE" != "1" ]; then
    record_skip "strict response-code coverage" "missing:$missing, but REPORT_TEST_REQUIRED_CODE_COVERAGE=$REQUIRED_CODE_COVERAGE"
  fi
}

print_header

# Auth preflight and identities.
auth_request "auth hello" "GET" "/hello" "200" "" ""
auth_request "auth health" "GET" "/health" "200|503" "" ""
login_primary_user
login_second_user
login_admin_token

if [ "$ACCESS_TOKEN" = "" ] || [ "$USER_ID" = "" ]; then
  echo
  echo "Cannot continue report API checks because primary user token or user id is missing."
  exit 1
fi

system_endpoint_tests
seed_calculator_data
seed_todo_data
protected_route_tests
report_core_tests
template_tests
schedule_tests
management_tests
admin_compatibility_checks
verify_response_code_coverage

# Final health after all API checks.
report_request "report health after api checks" "GET" "/health" "200|503" "" ""
assert_health_shape "report health after api checks"

# Summary.
echo
printf "%sSummary:%s %s total, %s passed, %s failed, %s skipped\n" "$BOLD" "$RESET" "$TEST_COUNT" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
echo "Report Base URL:       $REPORT_SERVICE_URL"
echo "Auth Base URL:         $AUTH_SERVICE_URL"
echo "Calculator Base URL:   ${CALCULATOR_SERVICE_URL:-<not provided>}"
echo "Todo Base URL:         ${TODO_SERVICE_URL:-<not provided>}"
echo "Admin Base URL:        ${ADMIN_SERVICE_URL:-<not provided>}"
echo "Test username:         $TEST_USERNAME"
echo "Primary user id:       $USER_ID"
echo "Second user id:        $SECOND_USER_ID"
echo "Admin user id:         $ADMIN_USER_ID"
echo "Created report id:     $CREATED_REPORT_ID"
echo "Conflict report id:    $CONFLICT_REPORT_ID"
echo "Completed report id:   $COMPLETED_REPORT_ID"
echo "Template id:           $TEMPLATE_ID"
echo "Schedule id:           $SCHEDULE_ID"
echo "Observed HTTP codes:   $OBSERVED_CODES"
if [ "$SAVE_RESPONSES" = "1" ]; then echo "Response files:        $TMP_DIR"; fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo
  echo "One or more report service checks failed. Review the failure messages above."
  exit 1
fi

echo
printf "%sAll required report service checks passed.%s\n" "$GREEN" "$RESET"
exit 0



# ./report_service_api_full_smoke_test.sh --report-url http://3.108.225.164:5052 --auth-url http://3.108.225.164:6062 --calculator-url http://3.108.225.164:2022 --todo-url http://3.108.225.164:3032 --admin-url http://3.108.225.164:1012


# ./report_service_api_full_smoke_test.sh --report-url http://3.108.225.164:5051 --auth-url http://3.108.225.164:6061 --calculator-url http://3.108.225.164:2021 --todo-url http://3.108.225.164:3031 --admin-url http://3.108.225.164:1011


# ./report_service_api_full_smoke_test.sh --report-url http://3.108.225.164:5050 --auth-url http://3.108.225.164:6060 --calculator-url http://3.108.225.164:2020 --todo-url http://3.108.225.164:3030 --admin-url http://3.108.225.164:1010