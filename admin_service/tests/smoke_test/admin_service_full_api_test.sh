#!/usr/bin/env bash
# Admin Service full API contract/integration test script.
#
# This script tests admin_service public routes, rejected routes, auth contract,
# every /v1/admin API route, invalid inputs, and optional projection seeding by
# calling auth_service, user_service, calculator_service, todo_list_service, and
# report_service.
#
# Usage:
#   chmod +x admin_service_full_api_test.sh
#   cp admin_service_full_api_test.env.example admin_service_full_api_test.env
#   ./admin_service_full_api_test.sh ./admin_service_full_api_test.env
#
# Safe by default:
#   ADMIN_TEST_MUTATE=0 uses fake IDs for side-effect endpoints and expects 404/409/501.
#   ADMIN_TEST_MUTATE=1 uses discovered IDs for suspend/activate/report commands.

set -u

SCRIPT_NAME="$(basename "$0")"
ENV_FILE="${1:-${ADMIN_TEST_ENV_FILE:-./admin_service_full_api_test.env}}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'USAGE'
Usage:
  ./admin_service_full_api_test.sh [env-file]

The env file is optional if all required variables are already exported.
See admin_service_full_api_test.env.example.

Important environment pairs:
  dev:   ADMIN_BASE_URL=http://<host>:1010 AUTH_BASE_URL=http://<host>:6060
  stage: ADMIN_BASE_URL=http://<host>:1011 AUTH_BASE_URL=http://<host>:6061
  prod:  ADMIN_BASE_URL=http://<host>:1012 AUTH_BASE_URL=http://<host>:6062

Key flags:
  ADMIN_TEST_VERBOSE=1
  ADMIN_TEST_SAVE_RESPONSES=1
  ADMIN_TEST_SEED_OTHER_SERVICES=1
  ADMIN_TEST_MUTATE=1
  ADMIN_TEST_STRICT=1
USAGE
  exit 0
fi

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
elif [ "${ADMIN_BASE_URL:-}" = "" ] || [ "${AUTH_BASE_URL:-}" = "" ]; then
  echo "Missing env file '$ENV_FILE' and ADMIN_BASE_URL/AUTH_BASE_URL are not exported."
  echo "Create one from admin_service_full_api_test.env.example or pass an env file path."
  exit 2
fi

ADMIN_BASE_URL="${ADMIN_BASE_URL:-http://192.168.56.50:1010}"
AUTH_BASE_URL="${AUTH_BASE_URL:-http://192.168.56.50:6060}"
USER_BASE_URL="${USER_BASE_URL:-}"
CALC_BASE_URL="${CALC_BASE_URL:-}"
TODO_BASE_URL="${TODO_BASE_URL:-}"
REPORT_BASE_URL="${REPORT_BASE_URL:-}"

ADMIN_TEST_AUTH_USERNAME="${ADMIN_TEST_AUTH_USERNAME:-admin}"
ADMIN_TEST_AUTH_PASSWORD="${ADMIN_TEST_AUTH_PASSWORD:-admin123}"
ADMIN_TEST_AUTH_LOGIN_PATH="${ADMIN_TEST_AUTH_LOGIN_PATH:-/v1/signin}"
ADMIN_TEST_AUTH_SIGNUP_PATH="${ADMIN_TEST_AUTH_SIGNUP_PATH:-/v1/signup}"

ADMIN_TOKEN="${ADMIN_TEST_ADMIN_TOKEN:-}"
NORMAL_TOKEN="${ADMIN_TEST_NORMAL_TOKEN:-}"
SECOND_TOKEN="${ADMIN_TEST_SECOND_TOKEN:-}"

TIMEOUT="${ADMIN_TEST_TIMEOUT:-25}"
VERBOSE="${ADMIN_TEST_VERBOSE:-0}"
SAVE_RESPONSES="${ADMIN_TEST_SAVE_RESPONSES:-0}"
CREATE_USERS="${ADMIN_TEST_CREATE_USERS:-1}"
SEED_OTHER_SERVICES="${ADMIN_TEST_SEED_OTHER_SERVICES:-1}"
MUTATE="${ADMIN_TEST_MUTATE:-0}"
STRICT="${ADMIN_TEST_STRICT:-0}"
PROJECTION_WAIT_SECONDS="${ADMIN_TEST_PROJECTION_WAIT_SECONDS:-8}"
ADMIN_FORWARDED_PROTO="${ADMIN_TEST_ADMIN_FORWARDED_PROTO:-https}"
TEST_USER_PASSWORD="${ADMIN_TEST_USER_PASSWORD:-Test1234!Aa}"
REPORT_FORMAT="${ADMIN_TEST_REPORT_FORMAT:-pdf}"
REPORT_TYPE="${ADMIN_TEST_REPORT_TYPE:-calculator_history_report}"

ADMIN_BASE_URL="${ADMIN_BASE_URL%/}"
AUTH_BASE_URL="${AUTH_BASE_URL%/}"
USER_BASE_URL="${USER_BASE_URL%/}"
CALC_BASE_URL="${CALC_BASE_URL%/}"
TODO_BASE_URL="${TODO_BASE_URL%/}"
REPORT_BASE_URL="${REPORT_BASE_URL%/}"

RUN_ID="$(date +%s)-$RANDOM"
TMP_DIR="$(mktemp -d)"
if [ "$SAVE_RESPONSES" = "1" ]; then
  echo "Response files kept at: $TMP_DIR"
else
  trap 'rm -rf "$TMP_DIR"' EXIT
fi

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TEST_COUNT=0

NORMAL_USER_ID=""
SECOND_USER_ID=""
ADMIN_USER_ID=""
DISCOVERED_USER_ID=""
REGISTRATION_ID=""
ACCESS_REQUEST_ID=""
ACCESS_GRANT_ID=""
CALCULATION_ID=""
TODO_ID=""
REPORT_ID=""
AUDIT_EVENT_ID=""
REPORT_AUDIT_EVENT_ID=""
TEMPLATE_ID="template-disabled"
SCHEDULE_ID="schedule-disabled"

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

new_uuid() {
  python3 - <<'PY'
import uuid
print(str(uuid.uuid4()))
PY
}

safe_name() { printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_'; }

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
        if key == '':
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
    if isinstance(obj, (dict, list)):
        print(json.dumps(obj, separators=(',', ':')))
    else:
        print(obj)
except Exception:
    print('')
PY
}

json_get_any() {
  local file="$1"; shift
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

short_body() {
  python3 - "$1" <<'PY'
import json, sys
p = sys.argv[1]
try:
    data = open(p, 'r', encoding='utf-8').read()
    try:
        obj = json.loads(data)
        def redact(x):
            if isinstance(x, dict):
                out = {}
                for k, v in x.items():
                    lk = k.lower()
                    if any(s in lk for s in ['password','token','secret','authorization','access_key','secret_key','credential']):
                        out[k] = '<redacted>'
                    else:
                        out[k] = redact(v)
                return out
            if isinstance(x, list):
                return [redact(i) for i in x]
            return x
        print(json.dumps(redact(obj), indent=2)[:2400])
    except Exception:
        print(data[:2400])
except Exception as e:
    print(f'<unable to read response: {e}>')
PY
}

record_pass() { TEST_COUNT=$((TEST_COUNT + 1)); PASS_COUNT=$((PASS_COUNT + 1)); printf "%s[PASS]%s %s\n" "$GREEN" "$RESET" "$1"; }
record_fail() { TEST_COUNT=$((TEST_COUNT + 1)); FAIL_COUNT=$((FAIL_COUNT + 1)); printf "%s[FAIL]%s %s\n" "$RED" "$RESET" "$1"; [ "${2:-}" != "" ] && echo "       $2"; }
record_skip() { TEST_COUNT=$((TEST_COUNT + 1)); SKIP_COUNT=$((SKIP_COUNT + 1)); printf "%s[SKIP]%s %s\n" "$YELLOW" "$RESET" "$1"; [ "${2:-}" != "" ] && echo "       $2"; }

print_section() { echo; printf "%s%s%s\n" "$BOLD" "$1" "$RESET"; }

last_file() { cat "$TMP_DIR/$(safe_name "$1").path" 2>/dev/null || true; }
last_code() { cat "$TMP_DIR/$(safe_name "$1").code" 2>/dev/null || true; }

request_to() {
  # request_to <base-url> <service> <name> <method> <path> <expected-regex> <body> <token>
  local base_url="$1" service="$2" name="$3" method="$4" path="$5" expected="$6" body="${7:-}" token="${8:-}"
  local safe outfile errfile code curl_exit req_id trace_id
  safe="$(safe_name "$name")"
  outfile="$TMP_DIR/$safe.json"
  errfile="$TMP_DIR/$safe.curlerr"
  req_id="req-$(new_uuid)"
  trace_id="$(new_uuid | tr -d '-')"

  local curl_args=(
    -sS
    --connect-timeout 5
    --max-time "$TIMEOUT"
    -o "$outfile"
    -w "%{http_code}"
    -X "$method"
    "$base_url$path"
    -H "accept: application/json"
    -H "X-Request-ID: $req_id"
    -H "X-Trace-ID: $trace_id"
    -H "X-Correlation-ID: $req_id"
  )

  if [ "$service" = "admin" ] && [ "$ADMIN_FORWARDED_PROTO" != "" ]; then
    curl_args+=( -H "X-Forwarded-Proto: $ADMIN_FORWARDED_PROTO" )
  fi
  if [ "$token" != "" ]; then
    curl_args+=( -H "Authorization: Bearer $token" )
  fi
  if [ "$body" != "" ]; then
    curl_args+=( -H "Content-Type: application/json" -d "$body" )
  fi

  code="$(curl "${curl_args[@]}" 2>"$errfile")"
  curl_exit=$?
  echo "$outfile" > "$TMP_DIR/$safe.path"
  echo "$code" > "$TMP_DIR/$safe.code"

  if [ "$VERBOSE" = "1" ]; then
    echo "--- $name response ($code) ---"
    short_body "$outfile"
    echo "-------------------------------"
  fi

  if [ "$curl_exit" -ne 0 ]; then
    record_fail "$name" "curl failed: $(cat "$errfile")"
    return 1
  fi
  if printf '%s' "$code" | grep -Eq "^($expected)$"; then
    record_pass "$name ($method $path -> HTTP $code)"
    return 0
  fi

  record_fail "$name" "$method $path expected HTTP $expected but got $code; response: $(short_body "$outfile" | tr '\n' ' ' | cut -c1-1200)"
  return 1
}

auth_request() { request_to "$AUTH_BASE_URL" "auth" "$@"; }
admin_request() { request_to "$ADMIN_BASE_URL" "admin" "$@"; }
user_request() { [ "$USER_BASE_URL" = "" ] && { record_skip "$1" "USER_BASE_URL not configured"; return 1; }; request_to "$USER_BASE_URL" "user" "$@"; }
calc_request() { [ "$CALC_BASE_URL" = "" ] && { record_skip "$1" "CALC_BASE_URL not configured"; return 1; }; request_to "$CALC_BASE_URL" "calculator" "$@"; }
todo_request() { [ "$TODO_BASE_URL" = "" ] && { record_skip "$1" "TODO_BASE_URL not configured"; return 1; }; request_to "$TODO_BASE_URL" "todo" "$@"; }
report_request() { [ "$REPORT_BASE_URL" = "" ] && { record_skip "$1" "REPORT_BASE_URL not configured"; return 1; }; request_to "$REPORT_BASE_URL" "report" "$@"; }

assert_json_status() {
  local name="$1" expected="$2" file status
  file="$(last_file "$name")"
  status="$(json_get "$file" "status")"
  if [ "$status" = "$expected" ]; then
    record_pass "$name envelope status is $expected"
  else
    record_fail "$name envelope status" "expected status=$expected, got '$status'"
  fi
}

assert_has_dependency_keys() {
  local name="$1" file missing key
  file="$(last_file "$name")"
  missing=""
  for key in jwt postgres redis kafka s3 mongodb apm elasticsearch; do
    [ "$(json_get "$file" "dependencies.$key.status")" = "" ] && missing="$missing $key"
  done
  if [ "$missing" = "" ]; then
    record_pass "$name dependency keys are complete"
  else
    record_fail "$name dependency keys are incomplete" "missing:$missing"
  fi
}

signin_admin() {
  if [ "$ADMIN_TOKEN" != "" ]; then
    record_pass "admin token provided by env"
    return 0
  fi
  local body file role status tenant
  body=$(cat <<JSON
{"username_or_email":"$ADMIN_TEST_AUTH_USERNAME","password":"$ADMIN_TEST_AUTH_PASSWORD","device_id":"admin-full-api-test"}
JSON
)
  auth_request "auth admin signin" "POST" "$ADMIN_TEST_AUTH_LOGIN_PATH" "200" "$body" "" || return 1
  file="$(last_file "auth admin signin")"
  ADMIN_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  ADMIN_USER_ID="$(json_get_any "$file" "data.user.user_id" "data.user.id" "data.user_id" "user_id" "data.user.sub")"
  role="$(json_get_any "$file" "data.user.role" "role")"
  status="$(json_get_any "$file" "data.user.admin_status" "admin_status")"
  tenant="$(json_get_any "$file" "data.user.tenant" "tenant")"
  [ "$ADMIN_TOKEN" != "" ] && record_pass "admin token extracted" || record_fail "admin token extracted" "auth signin did not return an access token"
  if [ "$role" = "admin" ] && [ "$status" = "approved" ]; then
    record_pass "auth admin token belongs to approved admin"
  else
    record_fail "auth admin token belongs to approved admin" "role=$role admin_status=$status tenant=$tenant"
  fi
}

signup_user() {
  local prefix="$1" username email body file token_var id_var
  username="adminapi_${prefix}_${RUN_ID}"
  email="${username}@example.com"
  body=$(cat <<JSON
{"username":"$username","email":"$email","password":"$TEST_USER_PASSWORD","full_name":"Admin API $prefix User","birthdate":"1998-05-20","gender":"other"}
JSON
)
  auth_request "auth signup $prefix user" "POST" "$ADMIN_TEST_AUTH_SIGNUP_PATH" "200|201|409" "$body" "" || true
  body=$(cat <<JSON
{"username_or_email":"$username","password":"$TEST_USER_PASSWORD","device_id":"admin-full-api-test-$prefix"}
JSON
)
  auth_request "auth signin $prefix user" "POST" "$ADMIN_TEST_AUTH_LOGIN_PATH" "200" "$body" "" || return 1
  file="$(last_file "auth signin $prefix user")"
  if [ "$prefix" = "normal" ]; then
    NORMAL_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
    NORMAL_USER_ID="$(json_get_any "$file" "data.user.user_id" "data.user.id" "data.user_id" "user_id" "data.user.sub")"
    [ "$NORMAL_TOKEN" != "" ] && record_pass "normal user token extracted" || record_fail "normal user token extracted"
    [ "$NORMAL_USER_ID" != "" ] && record_pass "normal user id extracted: $NORMAL_USER_ID" || record_skip "normal user id extracted" "auth response did not expose user id"
  else
    SECOND_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
    SECOND_USER_ID="$(json_get_any "$file" "data.user.user_id" "data.user.id" "data.user_id" "user_id" "data.user.sub")"
    [ "$SECOND_TOKEN" != "" ] && record_pass "second user token extracted" || record_fail "second user token extracted"
    [ "$SECOND_USER_ID" != "" ] && record_pass "second user id extracted: $SECOND_USER_ID" || record_skip "second user id extracted" "auth response did not expose user id"
  fi
}

prepare_tokens() {
  print_section "Auth preparation"
  auth_request "auth hello" "GET" "/hello" "200" "" ""
  auth_request "auth health" "GET" "/health" "200|503" "" ""
  signin_admin
  if [ "$CREATE_USERS" = "1" ]; then
    [ "$NORMAL_TOKEN" = "" ] && signup_user "normal" || record_pass "normal token provided by env"
    [ "$SECOND_TOKEN" = "" ] && signup_user "second" || record_pass "second token provided by env"
  fi
}

seed_other_services() {
  if [ "$SEED_OTHER_SERVICES" != "1" ]; then
    record_skip "cross-service seeding" "ADMIN_TEST_SEED_OTHER_SERVICES=$SEED_OTHER_SERVICES"
    return 0
  fi
  print_section "Cross-service seeding for admin projections"
  if [ "$NORMAL_TOKEN" = "" ]; then
    record_skip "cross-service seeding" "normal user token unavailable"
    return 0
  fi

  if [ "$USER_BASE_URL" != "" ]; then
    user_request "user profile me" "GET" "/v1/users/me" "200" "" "$NORMAL_TOKEN" || true
    user_request "user dashboard me" "GET" "/v1/users/me/dashboard" "200" "" "$NORMAL_TOKEN" || true
    if [ "$SECOND_USER_ID" != "" ]; then
      local access_body
      access_body=$(cat <<JSON
{"target_user_id":"$SECOND_USER_ID","resource_type":"calculator","scope":"calculator:history:read","reason":"Admin full API test access request","expires_at":"2030-01-01T00:00:00Z"}
JSON
)
      user_request "user create access request" "POST" "/v1/users/access-requests" "200|201|409" "$access_body" "$NORMAL_TOKEN" || true
      ACCESS_REQUEST_ID="$(json_get_any "$(last_file "user create access request")" "data.request_id" "data.access_request_id" "data.id" "request_id" "id")"
      [ "$ACCESS_REQUEST_ID" != "" ] && record_pass "access request id extracted from user_service: $ACCESS_REQUEST_ID" || record_skip "access request id extracted" "user_service did not expose access request id"
    fi
  fi

  if [ "$CALC_BASE_URL" != "" ]; then
    calc_request "calculator operations" "GET" "/v1/calculator/operations" "200" "" "$NORMAL_TOKEN" || true
    calc_request "calculator calculate add" "POST" "/v1/calculator/calculate" "200|201" '{"operation":"ADD","operands":[10,20]}' "$NORMAL_TOKEN" || true
    CALCULATION_ID="$(json_get_any "$(last_file "calculator calculate add")" "data.calculation_id" "data.id" "calculation_id" "id")"
    [ "$CALCULATION_ID" != "" ] && record_pass "calculation id extracted: $CALCULATION_ID" || record_skip "calculation id extracted" "calculator response did not expose id"
  fi

  if [ "$TODO_BASE_URL" != "" ]; then
    local todo_body
    todo_body=$(cat <<JSON
{"title":"Admin API test todo $RUN_ID","description":"Created by admin full API test","priority":"HIGH","due_date":"2030-01-01T00:00:00Z","tags":["admin-api-test"]}
JSON
)
    todo_request "todo create" "POST" "/v1/todos" "200|201" "$todo_body" "$NORMAL_TOKEN" || true
    TODO_ID="$(json_get_any "$(last_file "todo create")" "data.todo_id" "data.id" "todo_id" "id")"
    [ "$TODO_ID" != "" ] && record_pass "todo id extracted: $TODO_ID" || record_skip "todo id extracted" "todo response did not expose id"
    if [ "$TODO_ID" != "" ]; then
      todo_request "todo complete" "POST" "/v1/todos/$TODO_ID/complete" "200|409" "" "$NORMAL_TOKEN" || true
    fi
  fi

  if [ "$REPORT_BASE_URL" != "" ]; then
    report_request "report service types" "GET" "/v1/reports/types" "200" "" "$NORMAL_TOKEN" || true
    local report_body
    report_body=$(cat <<JSON
{"report_type":"$REPORT_TYPE","target_user_id":"$NORMAL_USER_ID","format":"$REPORT_FORMAT","date_from":"2026-05-01","date_to":"2030-01-01","filters":{},"options":{"source":"admin-full-api-test"}}
JSON
)
    report_request "report service create report" "POST" "/v1/reports" "200|201|202|400|409" "$report_body" "$NORMAL_TOKEN" || true
  fi

  if [ "$PROJECTION_WAIT_SECONDS" -gt 0 ] 2>/dev/null; then
    echo "Waiting ${PROJECTION_WAIT_SECONDS}s for Kafka projection updates..."
    sleep "$PROJECTION_WAIT_SECONDS"
  fi
}

system_route_tests() {
  print_section "Admin public/rejected route contract"
  admin_request "admin hello" "GET" "/hello" "200" "" ""
  assert_json_status "admin hello" "ok"
  admin_request "admin health" "GET" "/health" "200" "" ""
  assert_json_status "admin health" "ok"
  assert_has_dependency_keys "admin health"
  admin_request "admin docs" "GET" "/docs" "200" "" ""

  admin_request "admin root rejected" "GET" "/" "404" "" ""
  admin_request "admin live rejected" "GET" "/live" "404" "" ""
  admin_request "admin ready rejected" "GET" "/ready" "404" "" ""
  admin_request "admin healthy rejected" "GET" "/healthy" "404" "" ""
  admin_request "admin openapi rejected" "GET" "/openapi.json" "404" "" ""
  admin_request "admin swagger rejected" "GET" "/swagger" "404" "" ""
  admin_request "admin redoc rejected" "GET" "/redoc" "404" "" ""
  admin_request "admin swagger index rejected" "GET" "/swagger/index.html" "404" "" ""
  admin_request "admin swagger json rejected" "GET" "/swagger/v1/swagger.json" "404" "" ""
}

auth_contract_tests() {
  print_section "Admin auth/authorization contract"
  admin_request "admin dashboard without token" "GET" "/v1/admin/dashboard" "401" "" ""
  assert_json_status "admin dashboard without token" "error"
  admin_request "admin dashboard invalid token" "GET" "/v1/admin/dashboard" "401" "" "not-a-real-token"
  assert_json_status "admin dashboard invalid token" "error"
  if [ "$NORMAL_TOKEN" != "" ]; then
    admin_request "admin dashboard normal user forbidden" "GET" "/v1/admin/dashboard" "403" "" "$NORMAL_TOKEN"
    assert_json_status "admin dashboard normal user forbidden" "error"
  else
    record_skip "admin dashboard normal user forbidden" "normal user token unavailable"
  fi
  admin_request "admin dashboard approved admin" "GET" "/v1/admin/dashboard" "200" "" "$ADMIN_TOKEN"
  assert_json_status "admin dashboard approved admin" "ok"
}

discover_admin_ids() {
  print_section "Admin projection discovery"
  admin_request "admin list users discovery" "GET" "/v1/admin/users?limit=50" "200" "" "$ADMIN_TOKEN"
  local file
  file="$(last_file "admin list users discovery")"
  DISCOVERED_USER_ID="$(json_get_any "$file" "data.items.0.user_id" "data.items.0.id" "data.items.0.UserId")"
  [ "$DISCOVERED_USER_ID" != "" ] && record_pass "discovered admin user projection id: $DISCOVERED_USER_ID" || record_skip "discovered admin user projection id" "no users projected yet"
  [ "$NORMAL_USER_ID" != "" ] && DISCOVERED_USER_ID="$NORMAL_USER_ID"

  admin_request "admin list registrations discovery" "GET" "/v1/admin/registrations?limit=20" "200" "" "$ADMIN_TOKEN"
  file="$(last_file "admin list registrations discovery")"
  REGISTRATION_ID="$(json_get_any "$file" "data.items.0.request_id" "data.items.0.id" "data.items.0.user_id")"
  [ "$REGISTRATION_ID" != "" ] && record_pass "discovered registration id: $REGISTRATION_ID" || record_skip "discovered registration id" "no registration requests projected"

  admin_request "admin list access requests discovery" "GET" "/v1/admin/access-requests?limit=20" "200" "" "$ADMIN_TOKEN"
  file="$(last_file "admin list access requests discovery")"
  ACCESS_REQUEST_ID="${ACCESS_REQUEST_ID:-$(json_get_any "$file" "data.items.0.request_id" "data.items.0.id")}"
  [ "$ACCESS_REQUEST_ID" != "" ] && record_pass "discovered access request id: $ACCESS_REQUEST_ID" || record_skip "discovered access request id" "no access requests projected"

  admin_request "admin list access grants discovery" "GET" "/v1/admin/access-grants?limit=20" "200" "" "$ADMIN_TOKEN"
  file="$(last_file "admin list access grants discovery")"
  ACCESS_GRANT_ID="$(json_get_any "$file" "data.items.0.grant_id" "data.items.0.id")"
  [ "$ACCESS_GRANT_ID" != "" ] && record_pass "discovered access grant id: $ACCESS_GRANT_ID" || record_skip "discovered access grant id" "no access grants projected"

  admin_request "admin list calculations discovery" "GET" "/v1/admin/calculations?limit=20" "200" "" "$ADMIN_TOKEN"
  file="$(last_file "admin list calculations discovery")"
  CALCULATION_ID="${CALCULATION_ID:-$(json_get_any "$file" "data.items.0.calculation_id" "data.items.0.id")}"
  [ "$CALCULATION_ID" != "" ] && record_pass "discovered calculation id: $CALCULATION_ID" || record_skip "discovered calculation id" "no calculations projected"

  admin_request "admin list todos discovery" "GET" "/v1/admin/todos?limit=20" "200" "" "$ADMIN_TOKEN"
  file="$(last_file "admin list todos discovery")"
  TODO_ID="${TODO_ID:-$(json_get_any "$file" "data.items.0.todo_id" "data.items.0.id")}"
  [ "$TODO_ID" != "" ] && record_pass "discovered todo id: $TODO_ID" || record_skip "discovered todo id" "no todos projected"

  admin_request "admin list reports discovery" "GET" "/v1/admin/reports?limit=20" "200" "" "$ADMIN_TOKEN"
  file="$(last_file "admin list reports discovery")"
  REPORT_ID="${REPORT_ID:-$(json_get_any "$file" "data.items.0.report_id" "data.items.0.id")}"
  [ "$REPORT_ID" != "" ] && record_pass "discovered report id: $REPORT_ID" || record_skip "discovered report id" "no reports projected"

  admin_request "admin list audit discovery" "GET" "/v1/admin/audit?limit=20" "200" "" "$ADMIN_TOKEN"
  file="$(last_file "admin list audit discovery")"
  AUDIT_EVENT_ID="$(json_get_any "$file" "data.items.0.event_id" "data.items.0.id")"
  [ "$AUDIT_EVENT_ID" != "" ] && record_pass "discovered audit event id: $AUDIT_EVENT_ID" || record_skip "discovered audit event id" "no audit events found"

  admin_request "admin report audit discovery" "GET" "/v1/admin/reports/audit?limit=20" "200" "" "$ADMIN_TOKEN"
  file="$(last_file "admin report audit discovery")"
  REPORT_AUDIT_EVENT_ID="$(json_get_any "$file" "data.items.0.event_id" "data.items.0.id")"
  [ "$REPORT_AUDIT_EVENT_ID" != "" ] && record_pass "discovered report audit event id: $REPORT_AUDIT_EVENT_ID" || record_skip "discovered report audit event id" "no report audit events found"
}

admin_read_api_tests() {
  print_section "Admin read API coverage"
  local uid="${DISCOVERED_USER_ID:-missing-user-$(new_uuid)}"
  local missing_user="missing-user-$(new_uuid)"
  local missing_reg="missing-registration-$(new_uuid)"
  local missing_access_req="missing-access-request-$(new_uuid)"
  local missing_grant="missing-access-grant-$(new_uuid)"
  local missing_calc="missing-calculation-$(new_uuid)"
  local missing_todo="missing-todo-$(new_uuid)"
  local missing_report="missing-report-$(new_uuid)"
  local missing_audit="missing-audit-$(new_uuid)"

  admin_request "admin dashboard" "GET" "/v1/admin/dashboard" "200" "" "$ADMIN_TOKEN"
  admin_request "admin summary" "GET" "/v1/admin/summary" "200" "" "$ADMIN_TOKEN"

  admin_request "admin registrations list" "GET" "/v1/admin/registrations?limit=10" "200" "" "$ADMIN_TOKEN"
  if [ "$REGISTRATION_ID" != "" ]; then admin_request "admin registration get" "GET" "/v1/admin/registrations/$REGISTRATION_ID" "200|404" "" "$ADMIN_TOKEN"; fi
  admin_request "admin registration get missing" "GET" "/v1/admin/registrations/$missing_reg" "404" "" "$ADMIN_TOKEN"

  admin_request "admin access requests list" "GET" "/v1/admin/access-requests?limit=10" "200" "" "$ADMIN_TOKEN"
  if [ "$ACCESS_REQUEST_ID" != "" ]; then admin_request "admin access request get" "GET" "/v1/admin/access-requests/$ACCESS_REQUEST_ID" "200|404" "" "$ADMIN_TOKEN"; fi
  admin_request "admin access request missing" "GET" "/v1/admin/access-requests/$missing_access_req" "404" "" "$ADMIN_TOKEN"

  admin_request "admin access grants list" "GET" "/v1/admin/access-grants?limit=10" "200" "" "$ADMIN_TOKEN"
  if [ "$ACCESS_GRANT_ID" != "" ]; then admin_request "admin access grant get" "GET" "/v1/admin/access-grants/$ACCESS_GRANT_ID" "200|404" "" "$ADMIN_TOKEN"; fi
  admin_request "admin access grant missing" "GET" "/v1/admin/access-grants/$missing_grant" "404" "" "$ADMIN_TOKEN"

  admin_request "admin users list" "GET" "/v1/admin/users?limit=10" "200" "" "$ADMIN_TOKEN"
  if [ "$DISCOVERED_USER_ID" != "" ]; then
    admin_request "admin user get" "GET" "/v1/admin/users/$uid" "200|404" "" "$ADMIN_TOKEN"
    admin_request "admin user activity" "GET" "/v1/admin/users/$uid/activity" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user dashboard" "GET" "/v1/admin/users/$uid/dashboard" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user preferences" "GET" "/v1/admin/users/$uid/preferences" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user security context" "GET" "/v1/admin/users/$uid/security-context" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user rbac" "GET" "/v1/admin/users/$uid/rbac" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user effective permissions" "GET" "/v1/admin/users/$uid/effective-permissions" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user access requests" "GET" "/v1/admin/users/$uid/access-requests" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user access grants" "GET" "/v1/admin/users/$uid/access-grants" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user reports" "GET" "/v1/admin/users/$uid/reports" "200" "" "$ADMIN_TOKEN"
  fi
  admin_request "admin user get missing" "GET" "/v1/admin/users/$missing_user" "404" "" "$ADMIN_TOKEN"

  admin_request "admin calculations list" "GET" "/v1/admin/calculations?limit=10" "200" "" "$ADMIN_TOKEN"
  admin_request "admin calculations summary" "GET" "/v1/admin/calculations/summary" "200" "" "$ADMIN_TOKEN"
  admin_request "admin calculations failed" "GET" "/v1/admin/calculations/failed" "200" "" "$ADMIN_TOKEN"
  admin_request "admin calculations history cleared" "GET" "/v1/admin/calculations/history-cleared" "200" "" "$ADMIN_TOKEN"
  admin_request "admin calculations audit" "GET" "/v1/admin/calculations/audit" "200" "" "$ADMIN_TOKEN"
  if [ "$DISCOVERED_USER_ID" != "" ]; then
    admin_request "admin user calculations" "GET" "/v1/admin/calculations/users/$uid" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user calculations summary" "GET" "/v1/admin/calculations/users/$uid/summary" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user failed calculations" "GET" "/v1/admin/calculations/users/$uid/failed" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user calculations by operation" "GET" "/v1/admin/calculations/users/$uid/operations/ADD" "200" "" "$ADMIN_TOKEN"
  fi
  if [ "$CALCULATION_ID" != "" ]; then admin_request "admin calculation get" "GET" "/v1/admin/calculations/$CALCULATION_ID" "200|404" "" "$ADMIN_TOKEN"; fi
  admin_request "admin calculation missing" "GET" "/v1/admin/calculations/$missing_calc" "404" "" "$ADMIN_TOKEN"

  admin_request "admin todos list" "GET" "/v1/admin/todos?limit=10" "200" "" "$ADMIN_TOKEN"
  admin_request "admin todos summary" "GET" "/v1/admin/todos/summary" "200" "" "$ADMIN_TOKEN"
  admin_request "admin todos overdue" "GET" "/v1/admin/todos/overdue" "200" "" "$ADMIN_TOKEN"
  admin_request "admin todos today" "GET" "/v1/admin/todos/today" "200" "" "$ADMIN_TOKEN"
  admin_request "admin todos archived" "GET" "/v1/admin/todos/archived" "200" "" "$ADMIN_TOKEN"
  admin_request "admin todos deleted" "GET" "/v1/admin/todos/deleted" "200" "" "$ADMIN_TOKEN"
  admin_request "admin todos audit" "GET" "/v1/admin/todos/audit" "200" "" "$ADMIN_TOKEN"
  if [ "$DISCOVERED_USER_ID" != "" ]; then
    admin_request "admin user todos" "GET" "/v1/admin/todos/users/$uid" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user todos summary" "GET" "/v1/admin/todos/users/$uid/summary" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user todos overdue" "GET" "/v1/admin/todos/users/$uid/overdue" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user todos today" "GET" "/v1/admin/todos/users/$uid/today" "200" "" "$ADMIN_TOKEN"
    admin_request "admin user todos activity" "GET" "/v1/admin/todos/users/$uid/activity" "200" "" "$ADMIN_TOKEN"
  fi
  if [ "$TODO_ID" != "" ]; then
    admin_request "admin todo get" "GET" "/v1/admin/todos/$TODO_ID" "200|404" "" "$ADMIN_TOKEN"
    admin_request "admin todo history" "GET" "/v1/admin/todos/$TODO_ID/history" "200" "" "$ADMIN_TOKEN"
  fi
  admin_request "admin todo missing" "GET" "/v1/admin/todos/$missing_todo" "404" "" "$ADMIN_TOKEN"

  admin_request "admin reports list" "GET" "/v1/admin/reports?limit=10" "200" "" "$ADMIN_TOKEN"
  admin_request "admin reports summary" "GET" "/v1/admin/reports/summary" "200" "" "$ADMIN_TOKEN"
  admin_request "admin report types" "GET" "/v1/admin/reports/types" "200" "" "$ADMIN_TOKEN"
  admin_request "admin report type calculator" "GET" "/v1/admin/reports/types/$REPORT_TYPE" "200" "" "$ADMIN_TOKEN"
  admin_request "admin report templates list" "GET" "/v1/admin/reports/templates" "200" "" "$ADMIN_TOKEN"
  admin_request "admin report template get" "GET" "/v1/admin/reports/templates/$TEMPLATE_ID" "200" "" "$ADMIN_TOKEN"
  admin_request "admin report schedules list" "GET" "/v1/admin/reports/schedules" "200" "" "$ADMIN_TOKEN"
  admin_request "admin report schedule get" "GET" "/v1/admin/reports/schedules/$SCHEDULE_ID" "200" "" "$ADMIN_TOKEN"
  admin_request "admin report queue summary" "GET" "/v1/admin/reports/queue/summary" "200" "" "$ADMIN_TOKEN"
  admin_request "admin report audit" "GET" "/v1/admin/reports/audit" "200" "" "$ADMIN_TOKEN"
  if [ "$DISCOVERED_USER_ID" != "" ]; then admin_request "admin user report projections" "GET" "/v1/admin/reports/users/$uid" "200" "" "$ADMIN_TOKEN"; fi
  if [ "$REPORT_ID" != "" ]; then
    admin_request "admin report get" "GET" "/v1/admin/reports/$REPORT_ID" "200|404" "" "$ADMIN_TOKEN"
    admin_request "admin report metadata" "GET" "/v1/admin/reports/$REPORT_ID/metadata" "200|404" "" "$ADMIN_TOKEN"
    admin_request "admin report progress" "GET" "/v1/admin/reports/$REPORT_ID/progress" "200|404" "" "$ADMIN_TOKEN"
    admin_request "admin report events" "GET" "/v1/admin/reports/$REPORT_ID/events" "200" "" "$ADMIN_TOKEN"
    admin_request "admin report files" "GET" "/v1/admin/reports/$REPORT_ID/files" "200|404" "" "$ADMIN_TOKEN"
    admin_request "admin report preview" "GET" "/v1/admin/reports/$REPORT_ID/preview" "200|404" "" "$ADMIN_TOKEN"
    admin_request "admin report download info" "GET" "/v1/admin/reports/$REPORT_ID/download-info" "200|404" "" "$ADMIN_TOKEN"
  fi
  admin_request "admin report missing" "GET" "/v1/admin/reports/$missing_report" "404" "" "$ADMIN_TOKEN"
  admin_request "admin report metadata missing" "GET" "/v1/admin/reports/$missing_report/metadata" "404" "" "$ADMIN_TOKEN"

  admin_request "admin audit list" "GET" "/v1/admin/audit?limit=10" "200" "" "$ADMIN_TOKEN"
  if [ "$AUDIT_EVENT_ID" != "" ]; then admin_request "admin audit get" "GET" "/v1/admin/audit/$AUDIT_EVENT_ID" "200|404" "" "$ADMIN_TOKEN"; fi
  admin_request "admin audit missing" "GET" "/v1/admin/audit/$missing_audit" "404" "" "$ADMIN_TOKEN"
  if [ "$REPORT_AUDIT_EVENT_ID" != "" ]; then admin_request "admin report audit event get" "GET" "/v1/admin/reports/audit/$REPORT_AUDIT_EVENT_ID" "200|404" "" "$ADMIN_TOKEN"; fi
}

admin_invalid_and_mutation_tests() {
  print_section "Admin invalid-input and mutation coverage"
  local missing_reg="missing-registration-$(new_uuid)"
  local missing_access_req="missing-access-request-$(new_uuid)"
  local missing_grant="missing-access-grant-$(new_uuid)"
  local missing_user="missing-user-$(new_uuid)"
  local missing_report="missing-report-$(new_uuid)"
  local decision_body='{"reason":"Admin full API test"}'
  local access_body='{"scope":"calculator:history:read","expires_at":"2030-01-01T00:00:00Z","reason":"Admin full API test approval"}'

  admin_request "admin approve registration missing" "POST" "/v1/admin/registrations/$missing_reg/approve" "404" "$decision_body" "$ADMIN_TOKEN"
  admin_request "admin reject registration missing" "POST" "/v1/admin/registrations/$missing_reg/reject" "404|409" "$decision_body" "$ADMIN_TOKEN"
  admin_request "admin approve registration malformed" "POST" "/v1/admin/registrations/$missing_reg/approve" "400|404" "{" "$ADMIN_TOKEN"

  admin_request "admin approve access request missing" "POST" "/v1/admin/access-requests/$missing_access_req/approve" "404" "$access_body" "$ADMIN_TOKEN"
  admin_request "admin reject access request missing" "POST" "/v1/admin/access-requests/$missing_access_req/reject" "404|409" "$decision_body" "$ADMIN_TOKEN"
  admin_request "admin approve access request malformed" "POST" "/v1/admin/access-requests/$missing_access_req/approve" "400|404" "{" "$ADMIN_TOKEN"
  admin_request "admin revoke access grant missing" "POST" "/v1/admin/access-grants/$missing_grant/revoke" "404" "$decision_body" "$ADMIN_TOKEN"

  if [ "$MUTATE" = "1" ] && [ "${DISCOVERED_USER_ID:-}" != "" ]; then
    admin_request "admin suspend user" "POST" "/v1/admin/users/$DISCOVERED_USER_ID/suspend" "200" "$decision_body" "$ADMIN_TOKEN"
    admin_request "admin activate user" "POST" "/v1/admin/users/$DISCOVERED_USER_ID/activate" "200" "$decision_body" "$ADMIN_TOKEN"
    admin_request "admin force password reset" "POST" "/v1/admin/users/$DISCOVERED_USER_ID/force-password-reset" "200" "$decision_body" "$ADMIN_TOKEN"
  else
    admin_request "admin suspend missing user" "POST" "/v1/admin/users/$missing_user/suspend" "404" "$decision_body" "$ADMIN_TOKEN"
    admin_request "admin activate missing user" "POST" "/v1/admin/users/$missing_user/activate" "404" "$decision_body" "$ADMIN_TOKEN"
    admin_request "admin force password reset missing user" "POST" "/v1/admin/users/$missing_user/force-password-reset" "404" "$decision_body" "$ADMIN_TOKEN"
  fi

  admin_request "admin create report invalid format" "POST" "/v1/admin/reports" "400" '{"report_type":"calculator_history_report","format":"exe","filters":{},"options":{}}' "$ADMIN_TOKEN"
  admin_request "admin create report missing type" "POST" "/v1/admin/reports" "400" '{"format":"pdf","filters":{},"options":{}}' "$ADMIN_TOKEN"
  admin_request "admin create report malformed" "POST" "/v1/admin/reports" "400" "{" "$ADMIN_TOKEN"

  local report_body
  report_body=$(cat <<JSON
{"report_type":"$REPORT_TYPE","target_user_id":"${DISCOVERED_USER_ID:-$NORMAL_USER_ID}","format":"$REPORT_FORMAT","date_from":"2026-05-01","date_to":"2030-01-01","filters":{},"options":{"source":"admin-full-api-test"}}
JSON
)
  admin_request "admin create report valid" "POST" "/v1/admin/reports" "201" "$report_body" "$ADMIN_TOKEN"
  local created_file created_report
  created_file="$(last_file "admin create report valid")"
  created_report="$(json_get_any "$created_file" "data.report_id" "data.id" "report_id" "id")"
  [ "$created_report" != "" ] && REPORT_ID="$created_report"

  admin_request "admin cancel report missing" "POST" "/v1/admin/reports/$missing_report/cancel" "404" "$decision_body" "$ADMIN_TOKEN"
  admin_request "admin retry report missing" "POST" "/v1/admin/reports/$missing_report/retry" "404" "$decision_body" "$ADMIN_TOKEN"
  admin_request "admin regenerate report missing" "POST" "/v1/admin/reports/$missing_report/regenerate" "404" "$decision_body" "$ADMIN_TOKEN"
  admin_request "admin delete report missing" "DELETE" "/v1/admin/reports/$missing_report" "404" "" "$ADMIN_TOKEN"

  if [ "$MUTATE" = "1" ] && [ "$REPORT_ID" != "" ]; then
    admin_request "admin cancel report" "POST" "/v1/admin/reports/$REPORT_ID/cancel" "200|409" "$decision_body" "$ADMIN_TOKEN"
    admin_request "admin retry report" "POST" "/v1/admin/reports/$REPORT_ID/retry" "200|409" "$decision_body" "$ADMIN_TOKEN"
    admin_request "admin regenerate report" "POST" "/v1/admin/reports/$REPORT_ID/regenerate" "200|409" "$decision_body" "$ADMIN_TOKEN"
  fi

  admin_request "admin create template disabled" "POST" "/v1/admin/reports/templates" "501" '{"name":"disabled"}' "$ADMIN_TOKEN"
  admin_request "admin update template disabled" "PUT" "/v1/admin/reports/templates/$TEMPLATE_ID" "501" '{"name":"disabled"}' "$ADMIN_TOKEN"
  admin_request "admin activate template disabled" "POST" "/v1/admin/reports/templates/$TEMPLATE_ID/activate" "501" "" "$ADMIN_TOKEN"
  admin_request "admin deactivate template disabled" "POST" "/v1/admin/reports/templates/$TEMPLATE_ID/deactivate" "501" "" "$ADMIN_TOKEN"
  admin_request "admin create schedule disabled" "POST" "/v1/admin/reports/schedules" "501" '{"report_type":"todo_summary_report"}' "$ADMIN_TOKEN"
  admin_request "admin update schedule disabled" "PUT" "/v1/admin/reports/schedules/$SCHEDULE_ID" "501" '{"timezone":"UTC"}' "$ADMIN_TOKEN"
  admin_request "admin pause schedule disabled" "POST" "/v1/admin/reports/schedules/$SCHEDULE_ID/pause" "501" "" "$ADMIN_TOKEN"
  admin_request "admin resume schedule disabled" "POST" "/v1/admin/reports/schedules/$SCHEDULE_ID/resume" "501" "" "$ADMIN_TOKEN"
  admin_request "admin delete schedule disabled" "DELETE" "/v1/admin/reports/schedules/$SCHEDULE_ID" "501" "" "$ADMIN_TOKEN"
}

final_health_test() {
  print_section "Final health check"
  admin_request "admin health after all checks" "GET" "/health" "200" "" ""
  assert_json_status "admin health after all checks" "ok"
}

main() {
  echo "Admin Service Full API Test"
  echo "Admin Base URL:        $ADMIN_BASE_URL"
  echo "Auth Base URL:         $AUTH_BASE_URL"
  echo "User Base URL:         ${USER_BASE_URL:-<not configured>}"
  echo "Calculator Base URL:   ${CALC_BASE_URL:-<not configured>}"
  echo "Todo Base URL:         ${TODO_BASE_URL:-<not configured>}"
  echo "Report Base URL:       ${REPORT_BASE_URL:-<not configured>}"
  echo "Mutation mode:         $MUTATE"
  echo "Seed other services:   $SEED_OTHER_SERVICES"
  echo "Admin forwarded proto: ${ADMIN_FORWARDED_PROTO:-<none>}"
  echo "Run ID:                $RUN_ID"

  prepare_tokens
  if [ "$ADMIN_TOKEN" = "" ]; then
    echo "Cannot continue admin tests without approved admin token."
    exit 1
  fi

  seed_other_services
  system_route_tests
  auth_contract_tests
  discover_admin_ids
  admin_read_api_tests
  admin_invalid_and_mutation_tests
  final_health_test

  echo
  printf "%sSummary:%s %s total, %s passed, %s failed, %s skipped\n" "$BOLD" "$RESET" "$TEST_COUNT" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
  echo "Admin Base URL:       $ADMIN_BASE_URL"
  echo "Auth Base URL:        $AUTH_BASE_URL"
  echo "Mutation mode:        $MUTATE"
  echo "Discovered user id:   ${DISCOVERED_USER_ID:-<none>}"
  echo "Discovered reg id:    ${REGISTRATION_ID:-<none>}"
  echo "Discovered access id: ${ACCESS_REQUEST_ID:-<none>}"
  echo "Discovered grant id:  ${ACCESS_GRANT_ID:-<none>}"
  echo "Discovered calc id:   ${CALCULATION_ID:-<none>}"
  echo "Discovered todo id:   ${TODO_ID:-<none>}"
  echo "Discovered report id: ${REPORT_ID:-<none>}"
  [ "$SAVE_RESPONSES" = "1" ] && echo "Response directory:   $TMP_DIR"

  if [ "$FAIL_COUNT" -gt 0 ]; then
    echo
    echo "One or more admin service checks failed. Review failed responses above."
    exit 1
  fi

  echo
  printf "%sAll required admin service checks passed.%s\n" "$GREEN" "$RESET"
  exit 0
}

main "$@"
