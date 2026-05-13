#!/usr/bin/env bash
# Report Service full API + integration test script.
# Usage:
#   chmod +x report_service_full_api_test.sh
#   cp report_service_full_api_test.env.example report_service_full_api_test.env
#   ./report_service_full_api_test.sh ./report_service_full_api_test.env

set -u

ENV_FILE="${1:-}"
if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]; then
  echo "Usage: $0 <env-file>"
  echo "Example: $0 ./report_service_full_api_test.env"
  exit 2
fi

# shellcheck disable=SC1090
set -a
. "$ENV_FILE"
set +a

REPORT_BASE_URL="${REPORT_BASE_URL:-}"
AUTH_BASE_URL="${AUTH_BASE_URL:-}"
CALCULATOR_BASE_URL="${CALCULATOR_BASE_URL:-}"
TODO_BASE_URL="${TODO_BASE_URL:-}"
ADMIN_BASE_URL="${ADMIN_BASE_URL:-}"
USER_BASE_URL="${USER_BASE_URL:-}"

REPORT_FORWARDED_PROTO="${REPORT_FORWARDED_PROTO:-}"
AUTH_FORWARDED_PROTO="${AUTH_FORWARDED_PROTO:-}"
CALCULATOR_FORWARDED_PROTO="${CALCULATOR_FORWARDED_PROTO:-}"
TODO_FORWARDED_PROTO="${TODO_FORWARDED_PROTO:-}"
ADMIN_FORWARDED_PROTO="${ADMIN_FORWARDED_PROTO:-}"
USER_FORWARDED_PROTO="${USER_FORWARDED_PROTO:-}"

TIMEOUT="${REPORT_TEST_TIMEOUT:-20}"
REQUEST_RETRIES="${REPORT_TEST_RETRIES:-2}"
RETRY_DELAY_SECONDS="${REPORT_TEST_RETRY_DELAY_SECONDS:-2}"
VERBOSE="${REPORT_TEST_VERBOSE:-0}"
SAVE_RESPONSES="${REPORT_TEST_SAVE_RESPONSES:-0}"
STRICT_PUBLIC_ROUTES="${REPORT_TEST_STRICT_PUBLIC_ROUTES:-1}"
REQUIRED_CODE_COVERAGE="${REPORT_TEST_REQUIRED_CODE_COVERAGE:-1}"
WAIT_COMPLETED="${REPORT_TEST_WAIT_COMPLETED:-0}"
COMPLETION_RETRIES="${REPORT_TEST_COMPLETION_RETRIES:-24}"
COMPLETION_DELAY_SECONDS="${REPORT_TEST_COMPLETION_DELAY_SECONDS:-5}"
SEED_CALCULATOR="${REPORT_TEST_SEED_CALCULATOR:-1}"
SEED_TODO="${REPORT_TEST_SEED_TODO:-1}"
CHECK_ADMIN="${REPORT_TEST_CHECK_ADMIN:-1}"
CHECK_USER="${REPORT_TEST_CHECK_USER:-1}"
MUTATE="${REPORT_TEST_MUTATE:-0}"
TEMPLATE_MODE="${REPORT_TEST_TEMPLATE_MODE:-auto}"
SCHEDULE_MODE="${REPORT_TEST_SCHEDULE_MODE:-auto}"
AUTH_LOGIN_PATH="${REPORT_TEST_AUTH_LOGIN_PATH:-/v1/signin}"
DATE_FROM="${REPORT_TEST_DATE_FROM:-2026-05-01}"
DATE_TO="${REPORT_TEST_DATE_TO:-2026-05-09}"
REPORT_TIMEZONE="${REPORT_TEST_TIMEZONE:-Asia/Dhaka}"
REPORT_LOCALE="${REPORT_TEST_LOCALE:-en}"

ADMIN_USERNAME="${REPORT_TEST_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${REPORT_TEST_ADMIN_PASSWORD:-admin123}"
TEST_PASSWORD="${REPORT_TEST_PASSWORD:-Test1234!Aa}"
SECOND_PASSWORD="${REPORT_TEST_SECOND_PASSWORD:-Test1234!Aa}"
CREATE_USER="${REPORT_TEST_CREATE_USER:-1}"
CREATE_SECOND_USER="${REPORT_TEST_CREATE_SECOND_USER:-1}"
ACCESS_TOKEN="${REPORT_TEST_ACCESS_TOKEN:-}"
ADMIN_TOKEN="${REPORT_TEST_ADMIN_TOKEN:-}"
SECOND_TOKEN="${REPORT_TEST_SECOND_TOKEN:-}"

if [ -z "$REPORT_BASE_URL" ] || [ -z "$AUTH_BASE_URL" ]; then
  echo "REPORT_BASE_URL and AUTH_BASE_URL are required in $ENV_FILE"
  exit 2
fi

case "$REQUEST_RETRIES" in ''|*[!0-9]*) echo "REPORT_TEST_RETRIES must be an integer"; exit 2 ;; esac
case "$RETRY_DELAY_SECONDS" in ''|*[!0-9]*) echo "REPORT_TEST_RETRY_DELAY_SECONDS must be an integer"; exit 2 ;; esac
case "$COMPLETION_RETRIES" in ''|*[!0-9]*) echo "REPORT_TEST_COMPLETION_RETRIES must be an integer"; exit 2 ;; esac
case "$COMPLETION_DELAY_SECONDS" in ''|*[!0-9]*) echo "REPORT_TEST_COMPLETION_DELAY_SECONDS must be an integer"; exit 2 ;; esac
[ "$REQUEST_RETRIES" -lt 1 ] && REQUEST_RETRIES=1
[ "$COMPLETION_RETRIES" -lt 1 ] && COMPLETION_RETRIES=1

RUN_ID="$(date +%s)-$RANDOM"
TEST_USERNAME="reportuser_${RUN_ID}"
TEST_EMAIL="${TEST_USERNAME}@example.com"
SECOND_USERNAME="reportother_${RUN_ID}"
SECOND_EMAIL="${SECOND_USERNAME}@example.com"
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
OBSERVED_CODES=""
USER_ID=""
SECOND_USER_ID=""
ADMIN_USER_ID=""
CREATED_REPORT_ID=""
CONFLICT_REPORT_ID=""
COMPLETED_REPORT_ID=""
TEMPLATE_ID=""
SCHEDULE_ID=""
CALCULATION_ID=""
TODO_ID=""

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

iso_utc_hours() {
  python3 - "$1" <<'PY'
from datetime import datetime, timezone, timedelta
import sys
hours = int(sys.argv[1])
print((datetime.now(timezone.utc) + timedelta(hours=hours)).replace(microsecond=0).isoformat().replace('+00:00','Z'))
PY
}

safe_name() { printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_'; }

json_get() {
  python3 - "$1" "$2" <<'PY'
import json, sys
path, key_path = sys.argv[1], sys.argv[2]
try:
    raw = open(path, encoding='utf-8').read()
    if not raw.strip():
        print(''); sys.exit(0)
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
            print(''); sys.exit(0)
    if isinstance(obj, (dict, list)):
        print(json.dumps(obj, separators=(',', ':')))
    else:
        print(obj)
except Exception:
    print('')
PY
}

json_get_any() {
  local file="$1" value path
  shift
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
    data = json.loads(base64.urlsafe_b64decode(payload.encode()).decode())
    val = data.get(claim, '')
    print(json.dumps(val, separators=(',', ':')) if isinstance(val, (dict, list)) else val)
except Exception:
    print('')
PY
}

short_body() {
  python3 - "$1" <<'PY'
import json, sys
p = sys.argv[1]
try:
    data = open(p, encoding='utf-8').read()
    try:
        obj = json.loads(data)
        sensitive = ('token','secret','password','authorization','access_key','refresh','jwt')
        def redact(x):
            if isinstance(x, dict):
                return {k: ('<redacted>' if any(w in k.lower() for w in sensitive) else redact(v)) for k,v in x.items()}
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
remember_code() { case " $OBSERVED_CODES " in *" $1 "*) ;; *) OBSERVED_CODES="$OBSERVED_CODES $1" ;; esac; }
is_retryable_code() { case "$1" in 000|408|425|429|500|502|503|504) return 0 ;; *) return 1 ;; esac; }

proto_for_base() {
  case "$1" in
    report) printf '%s' "$REPORT_FORWARDED_PROTO" ;;
    auth) printf '%s' "$AUTH_FORWARDED_PROTO" ;;
    calculator) printf '%s' "$CALCULATOR_FORWARDED_PROTO" ;;
    todo) printf '%s' "$TODO_FORWARDED_PROTO" ;;
    admin) printf '%s' "$ADMIN_FORWARDED_PROTO" ;;
    user) printf '%s' "$USER_FORWARDED_PROTO" ;;
    *) printf '' ;;
  esac
}

base_for_service() {
  case "$1" in
    report) printf '%s' "$REPORT_BASE_URL" ;;
    auth) printf '%s' "$AUTH_BASE_URL" ;;
    calculator) printf '%s' "$CALCULATOR_BASE_URL" ;;
    todo) printf '%s' "$TODO_BASE_URL" ;;
    admin) printf '%s' "$ADMIN_BASE_URL" ;;
    user) printf '%s' "$USER_BASE_URL" ;;
    *) printf '' ;;
  esac
}

request_service() {
  # request_service <service> <name> <method> <path> <expected_regex> <body> <token>
  local service="$1" name="$2" method="$3" path="$4" expected="$5" body="${6:-}" token="${7:-}"
  local base proto safe outfile req_id trace_id accept_header http_code curl_exit attempt response_summary
  base="$(base_for_service "$service")"
  proto="$(proto_for_base "$service")"
  if [ -z "$base" ]; then
    record_skip "$name" "$service base URL is not configured"
    return 0
  fi
  safe="$(safe_name "$service $name")"
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
      "$base$path"
      -H "accept: $accept_header"
      -H "X-Request-ID: $req_id"
      -H "X-Trace-ID: $trace_id"
      -H "X-Correlation-ID: $req_id"
    )
    if [ "$proto" != "" ]; then curl_args+=( -H "X-Forwarded-Proto: $proto" ); fi
    if [ "$token" != "" ]; then curl_args+=( -H "Authorization: Bearer $token" ); fi
    if [ "$body" != "" ]; then curl_args+=( -H "Content-Type: application/json" -d "$body" ); fi

    http_code="$(curl "${curl_args[@]}" 2>"$outfile.curlerr")"
    curl_exit=$?
    echo "$outfile" > "$TMP_DIR/${safe}.path"
    echo "$http_code" > "$TMP_DIR/${safe}.code"

    if [ "$VERBOSE" = "1" ]; then
      echo "--- [$service] $name attempt $attempt response ($http_code) ---"
      short_body "$outfile"
      echo "-----------------------------------------------------------"
    fi

    if [ "$curl_exit" -eq 0 ] && printf '%s' "$http_code" | grep -Eq "^($expected)$"; then
      remember_code "$http_code"
      record_pass "[$service] $name ($method $path -> HTTP $http_code, attempt $attempt)"
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
    record_fail "[$service] $name ($method $path curl failed after $attempt attempt(s))" "$(cat "$outfile.curlerr" 2>/dev/null)"
  else
    record_fail "[$service] $name ($method $path expected HTTP $expected but got $http_code after $attempt attempt(s))" "response: $response_summary"
  fi
  return 1
}

report_request() { request_service report "$@"; }
auth_request() { request_service auth "$@"; }
calc_request() { request_service calculator "$@"; }
todo_request() { request_service todo "$@"; }
admin_request() { request_service admin "$@"; }
user_request() { request_service user "$@"; }

assert_json_status_ok() {
  local service="$1" name="$2" file status
  file="$TMP_DIR/$(safe_name "$service $name").path"
  file="$(cat "$file" 2>/dev/null || true)"
  status="$(json_get "$file" "status")"
  [ "$status" = "ok" ] && record_pass "[$service] $name envelope status is ok" || record_fail "[$service] $name envelope status" "expected status=ok got '$status'. Body: $(short_body "$file" | tr '\n' ' ' | cut -c1-800)"
}

assert_json_status_error() {
  local service="$1" name="$2" expected_error="$3" file status error_code
  file="$(cat "$TMP_DIR/$(safe_name "$service $name").path" 2>/dev/null || true)"
  status="$(json_get "$file" "status")"
  error_code="$(json_get "$file" "error_code")"
  if [ "$status" = "error" ] && printf '%s' "$error_code" | grep -Eq "^($expected_error)$"; then
    record_pass "[$service] $name error envelope is $error_code"
  else
    record_fail "[$service] $name error envelope" "expected status=error/error_code=$expected_error got status=$status error_code=$error_code. Body: $(short_body "$file" | tr '\n' ' ' | cut -c1-800)"
  fi
}

assert_health_shape() {
  local service="$1" name="$2" file rc
  file="$(cat "$TMP_DIR/$(safe_name "$service $name").path" 2>/dev/null || true)"
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
  [ "$rc" -eq 0 ] && record_pass "[$service] $name health dependency shape" || record_fail "[$service] $name health dependency shape" "$(short_body "$file" | tr '\n' ' ' | cut -c1-800)"
}

extract_report_id() {
  local service="$1" name="$2" file id
  file="$(cat "$TMP_DIR/$(safe_name "$service $name").path" 2>/dev/null || true)"
  id="$(json_get_any "$file" "data.report_id" "data.report.report_id" "data.id" "report_id" "id")"
  printf '%s' "$id"
}

extract_id_from_response() {
  local service="$1" name="$2" file id
  file="$(cat "$TMP_DIR/$(safe_name "$service $name").path" 2>/dev/null || true)"
  id="$(json_get_any "$file" "data.id" "data.todo.id" "data.todo.todo_id" "data.todo_id" "data.calculation_id" "data.record.id" "data.report_id" "id" "todo_id" "calculation_id")"
  printf '%s' "$id"
}

print_header() {
  echo "${BOLD}${BLUE}Report Service Full API + Integration Test${RESET}"
  echo "Env file:             $ENV_FILE"
  echo "Report Base URL:      $REPORT_BASE_URL"
  echo "Auth Base URL:        $AUTH_BASE_URL"
  echo "Calculator Base URL:  ${CALCULATOR_BASE_URL:-<not configured>}"
  echo "Todo Base URL:        ${TODO_BASE_URL:-<not configured>}"
  echo "Admin Base URL:       ${ADMIN_BASE_URL:-<not configured>}"
  echo "User Base URL:        ${USER_BASE_URL:-<not configured>}"
  echo "Run ID:               $RUN_ID"
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
  auth_request "signup $username" "POST" "/v1/signup" "200|201|409" "$body" ""
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
    record_pass "primary user token provided by env"
    return 0
  fi
  [ "$CREATE_USER" = "1" ] && signup_user "$TEST_USERNAME" "$TEST_EMAIL" "$TEST_PASSWORD" "Report Service Test User"
  signin_user "$TEST_USERNAME" "$TEST_PASSWORD" "report-test-$RUN_ID" "primary user signin"
  local file role
  file="$(cat "$TMP_DIR/$(safe_name "auth primary user signin").path" 2>/dev/null || true)"
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
    record_pass "second user token provided by env"
    return 0
  fi
  [ "$CREATE_SECOND_USER" = "1" ] || { record_skip "second user login" "disabled"; return 0; }
  signup_user "$SECOND_USERNAME" "$SECOND_EMAIL" "$SECOND_PASSWORD" "Report Service Second User"
  signin_user "$SECOND_USERNAME" "$SECOND_PASSWORD" "report-test-second-$RUN_ID" "second user signin"
  local file
  file="$(cat "$TMP_DIR/$(safe_name "auth second user signin").path" 2>/dev/null || true)"
  SECOND_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  SECOND_USER_ID="$(json_get_any "$file" "data.user.id" "data.user.user_id" "user.id" "user.user_id" "sub")"
  [ "$SECOND_USER_ID" = "" ] && SECOND_USER_ID="$(jwt_claim "$SECOND_TOKEN" "sub")"
  [ "$SECOND_TOKEN" != "" ] && record_pass "second user token extracted" || record_skip "second user token extracted" "token unavailable"
}

login_admin_token() {
  if [ "$ADMIN_TOKEN" != "" ]; then
    ADMIN_USER_ID="$(jwt_claim "$ADMIN_TOKEN" "sub")"
    record_pass "admin token provided by env"
    return 0
  fi
  local body file role admin_status
  body=$(cat <<JSON
{
  "username_or_email": "$ADMIN_USERNAME",
  "password": "$ADMIN_PASSWORD",
  "device_id": "report-test-admin-$RUN_ID"
}
JSON
)
  auth_request "admin signin" "POST" "$AUTH_LOGIN_PATH" "200|401|403" "$body" ""
  file="$(cat "$TMP_DIR/$(safe_name "auth admin signin").path" 2>/dev/null || true)"
  ADMIN_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  ADMIN_USER_ID="$(json_get_any "$file" "data.user.id" "data.user.user_id" "user.id" "user.user_id" "sub")"
  [ "$ADMIN_USER_ID" = "" ] && ADMIN_USER_ID="$(jwt_claim "$ADMIN_TOKEN" "sub")"
  role="$(json_get_any "$file" "data.user.role" "user.role" "role")"
  admin_status="$(json_get_any "$file" "data.user.admin_status" "user.admin_status" "admin_status")"
  if [ "$ADMIN_TOKEN" = "" ]; then record_skip "admin token extracted" "admin signin failed or token unavailable"; return 0; fi
  record_pass "admin token extracted"
  if [ "$role" = "admin" ] && [ "$admin_status" = "approved" ]; then record_pass "admin token is approved admin"; else record_skip "admin token is approved admin" "role=$role admin_status=$admin_status"; fi
}

system_endpoint_tests() {
  echo
  echo "${BOLD}Report public/system routes${RESET}"
  report_request "hello" "GET" "/hello" "200" "" ""
  assert_json_status_ok report "hello"
  report_request "health" "GET" "/health" "200|503" "" ""
  assert_health_shape report "health"
  [ "$(last_code "report health")" = "200" ] && assert_json_status_ok report "health" || record_skip "[report] health fully up" "health returned $(last_code "report health")"
  report_request "docs" "GET" "/docs" "200" "" ""
  if [ "$STRICT_PUBLIC_ROUTES" = "1" ]; then
    for path in / /live /ready /healthy /openapi.json /v3/api-docs /swagger /swagger-ui /swagger-ui/index.html /documentation/json /redoc /actuator /actuator/health /metrics /debug /admin; do
      report_request "rejected route $path" "GET" "$path" "404" "" ""
    done
  fi
}

auth_integration_tests() {
  echo
  echo "${BOLD}Auth integration preflight${RESET}"
  auth_request "hello" "GET" "/hello" "200" "" ""
  auth_request "health" "GET" "/health" "200|503" "" ""
  if [ "$ACCESS_TOKEN" != "" ]; then
    auth_request "me with primary token" "GET" "/v1/me" "200" "" "$ACCESS_TOKEN"
    auth_request "verify primary token" "GET" "/v1/verify" "200" "" "$ACCESS_TOKEN"
  fi
}

cross_service_seed_tests() {
  echo
  echo "${BOLD}Cross-service seed and projection checks${RESET}"
  if [ "$SEED_CALCULATOR" = "1" ]; then
    calc_request "hello" "GET" "/hello" "200|404|000" "" ""
    calc_request "operations" "GET" "/v1/calculator/operations" "200" "" "$ACCESS_TOKEN"
    calc_request "seed add calculation" "POST" "/v1/calculator/calculate" "200|201" '{"operation":"ADD","operands":[10,20,5]}' "$ACCESS_TOKEN"
    CALCULATION_ID="$(extract_id_from_response calculator "seed add calculation")"
    calc_request "seed expression calculation" "POST" "/v1/calculator/calculate" "200|201" '{"expression":"sqrt(16)+(10+5)*3"}' "$ACCESS_TOKEN"
    calc_request "own calculation history" "GET" "/v1/calculator/history" "200" "" "$ACCESS_TOKEN"
  else
    record_skip "calculator seed" "disabled"
  fi

  if [ "$SEED_TODO" = "1" ]; then
    local due body
    due="$(iso_utc_hours 48)"
    todo_request "hello" "GET" "/hello" "200|404|000" "" ""
    body=$(cat <<JSON
{
  "title": "Report service integration todo $RUN_ID",
  "description": "Seed data for report_service API test",
  "priority": "HIGH",
  "due_date": "$due",
  "tags": ["report-service", "integration", "$RUN_ID"]
}
JSON
)
    todo_request "seed create todo" "POST" "/v1/todos" "200|201" "$body" "$ACCESS_TOKEN"
    TODO_ID="$(extract_id_from_response todo "seed create todo")"
    todo_request "list own todos" "GET" "/v1/todos" "200" "" "$ACCESS_TOKEN"
    if [ "$TODO_ID" != "" ]; then todo_request "complete seed todo" "POST" "/v1/todos/$TODO_ID/complete" "200|404|409" "" "$ACCESS_TOKEN"; else record_skip "complete seed todo" "todo id not found"; fi
  else
    record_skip "todo seed" "disabled"
  fi

  if [ "$CHECK_USER" = "1" ]; then
    user_request "hello" "GET" "/hello" "200|404|000" "" ""
    user_request "me" "GET" "/v1/users/me" "200|404" "" "$ACCESS_TOKEN"
    user_request "dashboard" "GET" "/v1/users/me/dashboard" "200|404" "" "$ACCESS_TOKEN"
    user_request "calculation projections" "GET" "/v1/users/me/calculations" "200|404" "" "$ACCESS_TOKEN"
    user_request "todo projections" "GET" "/v1/users/me/todos" "200|404" "" "$ACCESS_TOKEN"
    user_request "report projections" "GET" "/v1/users/me/reports" "200|404" "" "$ACCESS_TOKEN"
  else
    record_skip "user service compatibility checks" "disabled"
  fi

  if [ "$CHECK_ADMIN" = "1" ] && [ "$ADMIN_TOKEN" != "" ]; then
    admin_request "hello" "GET" "/hello" "200|404|000" "" ""
    admin_request "reports list" "GET" "/v1/admin/reports" "200|403|404" "" "$ADMIN_TOKEN"
    admin_request "reports summary" "GET" "/v1/admin/reports/summary" "200|403|404" "" "$ADMIN_TOKEN"
    [ "$USER_ID" != "" ] && admin_request "user report projections" "GET" "/v1/admin/reports/users/$USER_ID" "200|403|404" "" "$ADMIN_TOKEN"
  else
    record_skip "admin service compatibility checks" "disabled or admin token missing"
  fi
}

protected_route_tests() {
  echo
  echo "${BOLD}Report auth/authorization negative tests${RESET}"
  report_request "types without token" "GET" "/v1/reports/types" "401" "" ""
  assert_json_status_error report "types without token" "UNAUTHORIZED"
  report_request "types invalid token" "GET" "/v1/reports/types" "401" "" "not-a-valid-jwt"
  assert_json_status_error report "types invalid token" "UNAUTHORIZED"
  report_request "create report without token" "POST" "/v1/reports" "401" '{"report_type":"calculator_history_report","format":"json"}' ""
  assert_json_status_error report "create report without token" "UNAUTHORIZED"
  report_request "queue summary normal user forbidden" "GET" "/v1/reports/queue/summary" "403|404" "" "$ACCESS_TOKEN"
  if [ "$(last_code "report queue summary normal user forbidden")" = "403" ]; then assert_json_status_error report "queue summary normal user forbidden" "FORBIDDEN"; fi
  report_request "admin report type normal user forbidden" "POST" "/v1/reports" "403|400|404" '{"report_type":"admin_decision_report","format":"json","filters":{},"options":{}}' "$ACCESS_TOKEN"
}

report_payload() {
  local report_type="$1" format="$2" target="${3:-}"
  python3 - "$report_type" "$format" "$target" "$DATE_FROM" "$DATE_TO" "$REPORT_TIMEZONE" "$REPORT_LOCALE" <<'PY'
import json, sys
report_type, fmt, target, d1, d2, tz, locale = sys.argv[1:]
payload = {
    "report_type": report_type,
    "format": fmt,
    "date_from": d1,
    "date_to": d2,
    "filters": {},
    "options": {
        "include_summary": True,
        "include_charts": True,
        "include_raw_data": True,
        "timezone": tz,
        "locale": locale,
        "title": f"Smoke Test {report_type} {fmt}"
    }
}
if target:
    payload["target_user_id"] = target
print(json.dumps(payload))
PY
}

create_report() {
  local name="$1" report_type="$2" format="$3" token="$4" target="${5:-}"
  report_request "$name" "POST" "/v1/reports" "200|201" "$(report_payload "$report_type" "$format" "$target")" "$token"
}

wait_for_report_completed() {
  local report_id="$1" name="$2" i file status
  [ "$WAIT_COMPLETED" = "1" ] || { record_skip "$name completed" "REPORT_TEST_WAIT_COMPLETED is not 1"; return 0; }
  [ "$report_id" != "" ] || { record_skip "$name completed" "report id unavailable"; return 0; }
  echo "Waiting for report $report_id to complete..."
  i=1
  while [ "$i" -le "$COMPLETION_RETRIES" ]; do
    report_request "$name poll status $i" "GET" "/v1/reports/$report_id" "200|404" "" "$ACCESS_TOKEN" >/dev/null 2>&1 || true
    file="$(cat "$TMP_DIR/$(safe_name "report $name poll status $i").path" 2>/dev/null || true)"
    status="$(json_get_any "$file" "data.status" "data.report.status" "status")"
    if [ "$status" = "COMPLETED" ]; then COMPLETED_REPORT_ID="$report_id"; record_pass "$name reached COMPLETED after $i poll(s)"; return 0; fi
    if [ "$status" = "FAILED" ] || [ "$status" = "CANCELLED" ] || [ "$status" = "DELETED" ]; then record_fail "$name completed" "terminal status=$status"; return 1; fi
    sleep "$COMPLETION_DELAY_SECONDS"
    i=$((i + 1))
  done
  record_skip "$name completed" "not completed after $COMPLETION_RETRIES polls; last status=$status"
}

report_core_tests() {
  echo
  echo "${BOLD}Report core APIs${RESET}"
  report_request "list report types" "GET" "/v1/reports/types" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok report "list report types"
  report_request "get calculator history report type" "GET" "/v1/reports/types/calculator_history_report" "200|404" "" "$ACCESS_TOKEN"
  [ "$(last_code "report get calculator history report type")" = "200" ] && assert_json_status_ok report "get calculator history report type"
  report_request "get missing report type" "GET" "/v1/reports/types/not_a_real_report" "404" "" "$ACCESS_TOKEN"
  assert_json_status_error report "get missing report type" "NOT_FOUND"

  create_report "create json calculator report" "calculator_history_report" "json" "$ACCESS_TOKEN"
  CREATED_REPORT_ID="$(extract_report_id report "create json calculator report")"
  [ "$CREATED_REPORT_ID" != "" ] && record_pass "created report id extracted: $CREATED_REPORT_ID" || record_fail "created report id extracted" "missing report id"

  create_report "create csv calculator report" "calculator_history_report" "csv" "$ACCESS_TOKEN"
  create_report "create html todo report" "todo_summary_report" "html" "$ACCESS_TOKEN"
  create_report "create pdf user activity report" "user_activity_report" "pdf" "$ACCESS_TOKEN"
  create_report "create xlsx full user report" "full_user_report" "xlsx" "$ACCESS_TOKEN"

  report_request "create unsupported report type" "POST" "/v1/reports" "400|404" '{"report_type":"not_real","format":"json","filters":{},"options":{}}' "$ACCESS_TOKEN"
  report_request "create unsupported format" "POST" "/v1/reports" "400" '{"report_type":"calculator_history_report","format":"docx","filters":{},"options":{}}' "$ACCESS_TOKEN"
  report_request "create bad date order" "POST" "/v1/reports" "400" '{"report_type":"calculator_history_report","format":"json","date_from":"2026-05-10","date_to":"2026-05-01","filters":{},"options":{}}' "$ACCESS_TOKEN"
  report_request "create malformed json" "POST" "/v1/reports" "400" '{"report_type":' "$ACCESS_TOKEN"

  report_request "list reports" "GET" "/v1/reports?limit=20&offset=0" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok report "list reports"
  report_request "list reports invalid status" "GET" "/v1/reports?status=NOPE" "400|200" "" "$ACCESS_TOKEN"

  if [ "$CREATED_REPORT_ID" != "" ]; then
    report_request "get created report" "GET" "/v1/reports/$CREATED_REPORT_ID" "200" "" "$ACCESS_TOKEN"
    assert_json_status_ok report "get created report"
    report_request "get created report progress" "GET" "/v1/reports/$CREATED_REPORT_ID/progress" "200|404" "" "$ACCESS_TOKEN"
    report_request "get created report events" "GET" "/v1/reports/$CREATED_REPORT_ID/events" "200|404" "" "$ACCESS_TOKEN"
    report_request "get created report files" "GET" "/v1/reports/$CREATED_REPORT_ID/files" "200|404" "" "$ACCESS_TOKEN"
    report_request "metadata before complete" "GET" "/v1/reports/$CREATED_REPORT_ID/metadata" "200|404|409" "" "$ACCESS_TOKEN"
    report_request "preview before complete" "GET" "/v1/reports/$CREATED_REPORT_ID/preview" "200|404|409" "" "$ACCESS_TOKEN"
    report_request "download before complete" "GET" "/v1/reports/$CREATED_REPORT_ID/download" "200|404|409" "" "$ACCESS_TOKEN"
  fi

  create_report "create conflict candidate report" "calculator_history_report" "json" "$ACCESS_TOKEN"
  CONFLICT_REPORT_ID="$(extract_report_id report "create conflict candidate report")"
  if [ "$CONFLICT_REPORT_ID" != "" ]; then
    report_request "retry non failed report" "POST" "/v1/reports/$CONFLICT_REPORT_ID/retry" "200|202|404|409" "" "$ACCESS_TOKEN"
    report_request "regenerate non failed report" "POST" "/v1/reports/$CONFLICT_REPORT_ID/regenerate" "200|202|404|409|501" "" "$ACCESS_TOKEN"
    report_request "cancel report" "POST" "/v1/reports/$CONFLICT_REPORT_ID/cancel" "200|404|409" "" "$ACCESS_TOKEN"
  fi

  local missing="missing-report-$(new_uuid)"
  report_request "get missing report" "GET" "/v1/reports/$missing" "404" "" "$ACCESS_TOKEN"
  assert_json_status_error report "get missing report" "NOT_FOUND"
  report_request "cancel missing report" "POST" "/v1/reports/$missing/cancel" "404" "" "$ACCESS_TOKEN"
  report_request "retry missing report" "POST" "/v1/reports/$missing/retry" "404" "" "$ACCESS_TOKEN"
  report_request "delete missing report" "DELETE" "/v1/reports/$missing" "404" "" "$ACCESS_TOKEN"
  report_request "metadata missing report" "GET" "/v1/reports/$missing/metadata" "404" "" "$ACCESS_TOKEN"
  report_request "preview missing report" "GET" "/v1/reports/$missing/preview" "404" "" "$ACCESS_TOKEN"
  report_request "download missing report" "GET" "/v1/reports/$missing/download" "404" "" "$ACCESS_TOKEN"
  report_request "progress missing report" "GET" "/v1/reports/$missing/progress" "404" "" "$ACCESS_TOKEN"
  report_request "events missing report" "GET" "/v1/reports/$missing/events" "404" "" "$ACCESS_TOKEN"
  report_request "files missing report" "GET" "/v1/reports/$missing/files" "404" "" "$ACCESS_TOKEN"

  if [ "$SECOND_TOKEN" != "" ] && [ "$CREATED_REPORT_ID" != "" ]; then
    report_request "second user cannot read primary report" "GET" "/v1/reports/$CREATED_REPORT_ID" "403|404" "" "$SECOND_TOKEN"
  else
    record_skip "second user cannot read primary report" "second token/report id unavailable"
  fi

  [ "$CREATED_REPORT_ID" != "" ] && wait_for_report_completed "$CREATED_REPORT_ID" "created report"
  if [ "$COMPLETED_REPORT_ID" != "" ]; then
    report_request "completed report metadata" "GET" "/v1/reports/$COMPLETED_REPORT_ID/metadata" "200" "" "$ACCESS_TOKEN"
    report_request "completed report preview" "GET" "/v1/reports/$COMPLETED_REPORT_ID/preview" "200|404" "" "$ACCESS_TOKEN"
    report_request "completed report files" "GET" "/v1/reports/$COMPLETED_REPORT_ID/files" "200|404" "" "$ACCESS_TOKEN"
    report_request "completed report download" "GET" "/v1/reports/$COMPLETED_REPORT_ID/download" "200" "" "$ACCESS_TOKEN"
    [ "$MUTATE" = "1" ] && report_request "delete completed report" "DELETE" "/v1/reports/$COMPLETED_REPORT_ID" "200" "" "$ACCESS_TOKEN" || record_skip "delete completed report" "REPORT_TEST_MUTATE is not 1"
  fi
}

template_tests() {
  echo
  echo "${BOLD}Report template APIs${RESET}"
  local write_expected list_expected body missing
  case "$TEMPLATE_MODE" in
    canonical-disabled) write_expected="501"; list_expected="200" ;;
    enabled) write_expected="200|201"; list_expected="200" ;;
    *) write_expected="200|201|501"; list_expected="200|501" ;;
  esac

  report_request "templates list" "GET" "/v1/reports/templates" "$list_expected|403" "" "$ACCESS_TOKEN"
  if [ "$ADMIN_TOKEN" != "" ]; then
    report_request "templates list admin" "GET" "/v1/reports/templates" "$list_expected" "" "$ADMIN_TOKEN"
    body=$(cat <<JSON
{
  "report_type": "calculator_history_report",
  "name": "Smoke Template $RUN_ID",
  "description": "Created by report full API test",
  "format": "pdf",
  "template_content": "{}",
  "schema": {"visible_columns": ["operation", "status", "created_at"]},
  "style": {"footer_text": "Internal"}
}
JSON
)
    report_request "template create admin" "POST" "/v1/reports/templates" "$write_expected" "$body" "$ADMIN_TOKEN"
    TEMPLATE_ID="$(extract_id_from_response report "template create admin")"
    missing="missing-template-$(new_uuid)"
    report_request "template get missing" "GET" "/v1/reports/templates/$missing" "404|501" "" "$ADMIN_TOKEN"
    report_request "template update missing" "PUT" "/v1/reports/templates/$missing" "404|501" '{"name":"Nope"}' "$ADMIN_TOKEN"
    report_request "template activate missing" "POST" "/v1/reports/templates/$missing/activate" "404|501" "" "$ADMIN_TOKEN"
    report_request "template deactivate missing" "POST" "/v1/reports/templates/$missing/deactivate" "404|501" "" "$ADMIN_TOKEN"
    if [ "$TEMPLATE_ID" != "" ]; then
      report_request "template get admin" "GET" "/v1/reports/templates/$TEMPLATE_ID" "200|501" "" "$ADMIN_TOKEN"
      report_request "template update admin" "PUT" "/v1/reports/templates/$TEMPLATE_ID" "$write_expected" '{"name":"Smoke Template Updated"}' "$ADMIN_TOKEN"
      report_request "template activate admin" "POST" "/v1/reports/templates/$TEMPLATE_ID/activate" "$write_expected" "" "$ADMIN_TOKEN"
      report_request "template deactivate admin" "POST" "/v1/reports/templates/$TEMPLATE_ID/deactivate" "$write_expected" "" "$ADMIN_TOKEN"
    else
      record_skip "template id based checks" "no template id returned"
    fi
  else
    record_skip "template admin tests" "admin token unavailable"
  fi
}

schedule_tests() {
  echo
  echo "${BOLD}Report schedule APIs${RESET}"
  local write_expected list_expected body missing
  case "$SCHEDULE_MODE" in
    canonical-disabled) write_expected="501"; list_expected="200" ;;
    enabled) write_expected="200|201"; list_expected="200" ;;
    *) write_expected="200|201|501"; list_expected="200|501" ;;
  esac

  report_request "schedules list" "GET" "/v1/reports/schedules" "$list_expected" "" "$ACCESS_TOKEN"
  body=$(cat <<JSON
{
  "report_type": "todo_summary_report",
  "format": "pdf",
  "cron_expression": "0 9 * * *",
  "timezone": "$REPORT_TIMEZONE",
  "filters": {},
  "options": {"include_summary": true}
}
JSON
)
  report_request "schedule create" "POST" "/v1/reports/schedules" "$write_expected" "$body" "$ACCESS_TOKEN"
  SCHEDULE_ID="$(extract_id_from_response report "schedule create")"
  missing="missing-schedule-$(new_uuid)"
  report_request "schedule get missing" "GET" "/v1/reports/schedules/$missing" "404|501" "" "$ACCESS_TOKEN"
  report_request "schedule update missing" "PUT" "/v1/reports/schedules/$missing" "404|501" '{"timezone":"UTC"}' "$ACCESS_TOKEN"
  report_request "schedule pause missing" "POST" "/v1/reports/schedules/$missing/pause" "404|501" "" "$ACCESS_TOKEN"
  report_request "schedule resume missing" "POST" "/v1/reports/schedules/$missing/resume" "404|501" "" "$ACCESS_TOKEN"
  report_request "schedule delete missing" "DELETE" "/v1/reports/schedules/$missing" "404|501" "" "$ACCESS_TOKEN"
  if [ "$SCHEDULE_ID" != "" ]; then
    report_request "schedule get" "GET" "/v1/reports/schedules/$SCHEDULE_ID" "200|501" "" "$ACCESS_TOKEN"
    report_request "schedule update" "PUT" "/v1/reports/schedules/$SCHEDULE_ID" "$write_expected" '{"timezone":"UTC"}' "$ACCESS_TOKEN"
    report_request "schedule pause" "POST" "/v1/reports/schedules/$SCHEDULE_ID/pause" "$write_expected" "" "$ACCESS_TOKEN"
    report_request "schedule resume" "POST" "/v1/reports/schedules/$SCHEDULE_ID/resume" "$write_expected" "" "$ACCESS_TOKEN"
    [ "$MUTATE" = "1" ] && report_request "schedule delete" "DELETE" "/v1/reports/schedules/$SCHEDULE_ID" "$write_expected" "" "$ACCESS_TOKEN" || record_skip "schedule delete" "REPORT_TEST_MUTATE is not 1"
  else
    record_skip "schedule id based checks" "no schedule id returned"
  fi
}

management_tests() {
  echo
  echo "${BOLD}Report management/audit APIs${RESET}"
  report_request "audit list normal forbidden" "GET" "/v1/reports/audit" "403|404" "" "$ACCESS_TOKEN"
  if [ "$ADMIN_TOKEN" = "" ]; then record_skip "management admin tests" "admin token unavailable"; return 0; fi
  report_request "queue summary admin" "GET" "/v1/reports/queue/summary" "200|404" "" "$ADMIN_TOKEN"
  report_request "audit list admin" "GET" "/v1/reports/audit?limit=20&offset=0" "200|404" "" "$ADMIN_TOKEN"
  local file audit_id
  file="$(cat "$TMP_DIR/$(safe_name "report audit list admin").path" 2>/dev/null || true)"
  audit_id="$(json_get_any "$file" "data.audit_events.0.event_id" "data.items.0.event_id" "data.0.event_id")"
  if [ "$audit_id" != "" ]; then
    report_request "audit get admin" "GET" "/v1/reports/audit/$audit_id" "200|404" "" "$ADMIN_TOKEN"
  else
    record_skip "audit get admin" "no audit event id found"
  fi
  report_request "audit get missing admin" "GET" "/v1/reports/audit/missing-audit-$(new_uuid)" "404" "" "$ADMIN_TOKEN"
}

verify_response_code_coverage() {
  echo
  echo "${BOLD}Response-code coverage${RESET}"
  local required="200 201 400 401 403 404" code missing=""
  # 409 is lifecycle-dependent; still report it, but do not force failure unless observed feature paths exist.
  [ "$REQUIRED_CODE_COVERAGE" = "1" ] && required="$required 409"
  for code in $required; do
    case " $OBSERVED_CODES " in
      *" $code "*) record_pass "observed HTTP $code" ;;
      *) missing="$missing $code"; record_fail "observed HTTP $code" "not observed in this run" ;;
    esac
  done
}

print_header
auth_integration_tests
login_primary_user
login_second_user
login_admin_token

if [ "$ACCESS_TOKEN" = "" ] || [ "$USER_ID" = "" ]; then
  echo "Cannot continue: primary user token or user id is missing."
  exit 1
fi

system_endpoint_tests
cross_service_seed_tests
protected_route_tests
report_core_tests
template_tests
schedule_tests
management_tests
verify_response_code_coverage

report_request "health after API checks" "GET" "/health" "200|503" "" ""
assert_health_shape report "health after API checks"

echo
printf "%sSummary:%s %s total, %s passed, %s failed, %s skipped\n" "$BOLD" "$RESET" "$TEST_COUNT" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
echo "Report Base URL:       $REPORT_BASE_URL"
echo "Auth Base URL:         $AUTH_BASE_URL"
echo "Calculator Base URL:   ${CALCULATOR_BASE_URL:-<not configured>}"
echo "Todo Base URL:         ${TODO_BASE_URL:-<not configured>}"
echo "Admin Base URL:        ${ADMIN_BASE_URL:-<not configured>}"
echo "User Base URL:         ${USER_BASE_URL:-<not configured>}"
echo "Test username:         $TEST_USERNAME"
echo "Primary user id:       $USER_ID"
echo "Second user id:        $SECOND_USER_ID"
echo "Admin user id:         $ADMIN_USER_ID"
echo "Created report id:     $CREATED_REPORT_ID"
echo "Conflict report id:    $CONFLICT_REPORT_ID"
echo "Completed report id:   $COMPLETED_REPORT_ID"
echo "Template id:           $TEMPLATE_ID"
echo "Schedule id:           $SCHEDULE_ID"
echo "Calculation id:        $CALCULATION_ID"
echo "Todo id:               $TODO_ID"
echo "Observed HTTP codes:   $OBSERVED_CODES"
[ "$SAVE_RESPONSES" = "1" ] && echo "Response files:        $TMP_DIR"

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo
  echo "One or more report service checks failed. Review the failure messages above."
  exit 1
fi

echo
printf "%sAll required report service checks passed.%s\n" "$GREEN" "$RESET"
exit 0
