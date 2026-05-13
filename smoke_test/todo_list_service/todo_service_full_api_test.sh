#!/usr/bin/env bash
# Todo Service full API + integration test script
# Usage:
#   cp todo_service_full_api_test.env.example todo_service_full_api_test.env
#   chmod +x todo_service_full_api_test.sh
#   ./todo_service_full_api_test.sh ./todo_service_full_api_test.env
#
# This script tests todo_list_service/todo_service public routes, protected APIs,
# valid/invalid todo CRUD/status flows, admin hard-delete authorization, and
# optional downstream projections in admin_service, user_service, and report_service.

set -u

if [ "${1:-}" = "" ]; then
  echo "Usage: $0 <env-file>"
  echo "Example: $0 ./todo_service_full_api_test.env"
  exit 2
fi

ENV_FILE="$1"
if [ ! -f "$ENV_FILE" ]; then
  echo "Env file not found: $ENV_FILE"
  exit 2
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

TODO_BASE_URL="${TODO_BASE_URL:-}"
AUTH_BASE_URL="${AUTH_BASE_URL:-}"
ADMIN_BASE_URL="${ADMIN_BASE_URL:-}"
USER_BASE_URL="${USER_BASE_URL:-}"
REPORT_BASE_URL="${REPORT_BASE_URL:-}"
TIMEOUT="${TODO_TEST_TIMEOUT:-25}"
VERBOSE="${TODO_TEST_VERBOSE:-0}"
RUN_DOWNSTREAM="${TODO_TEST_RUN_DOWNSTREAM:-1}"
RUN_MUTATIONS="${TODO_TEST_RUN_MUTATIONS:-1}"
EVENT_WAIT_SECONDS="${TODO_TEST_EVENT_WAIT_SECONDS:-3}"
TENANT="${TODO_TEST_TENANT:-dev}"
REPORT_FORMAT="${TODO_TEST_REPORT_FORMAT:-pdf}"
REPORT_TYPE="${TODO_TEST_REPORT_TYPE:-}"

AUTH_ADMIN_USERNAME="${TODO_TEST_ADMIN_USERNAME:-admin}"
AUTH_ADMIN_PASSWORD="${TODO_TEST_ADMIN_PASSWORD:-admin123}"
USER_PASSWORD="${TODO_TEST_USER_PASSWORD:-Test1234!Aa}"
SECOND_USER_PASSWORD="${TODO_TEST_SECOND_USER_PASSWORD:-Test1234!Aa}"

TODO_FORWARDED_PROTO="${TODO_FORWARDED_PROTO:-}"
AUTH_FORWARDED_PROTO="${AUTH_FORWARDED_PROTO:-}"
ADMIN_FORWARDED_PROTO="${ADMIN_FORWARDED_PROTO:-}"
USER_FORWARDED_PROTO="${USER_FORWARDED_PROTO:-}"
REPORT_FORWARDED_PROTO="${REPORT_FORWARDED_PROTO:-}"

if [ -z "$TODO_BASE_URL" ] || [ -z "$AUTH_BASE_URL" ]; then
  echo "TODO_BASE_URL and AUTH_BASE_URL are required in $ENV_FILE"
  exit 2
fi

TODO_BASE_URL="${TODO_BASE_URL%/}"
AUTH_BASE_URL="${AUTH_BASE_URL%/}"
ADMIN_BASE_URL="${ADMIN_BASE_URL%/}"
USER_BASE_URL="${USER_BASE_URL%/}"
REPORT_BASE_URL="${REPORT_BASE_URL%/}"

RUN_ID="$(date +%s)-$RANDOM"
PRIMARY_USERNAME="todouser_${RUN_ID}"
PRIMARY_EMAIL="${PRIMARY_USERNAME}@example.com"
SECOND_USERNAME="todocross_${RUN_ID}"
SECOND_EMAIL="${SECOND_USERNAME}@example.com"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TEST_COUNT=0

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

iso_datetime_days_from_now() {
  python3 - "$1" <<'PY'
from datetime import datetime, timezone, timedelta
import sys
n = int(sys.argv[1])
print((datetime.now(timezone.utc) + timedelta(days=n)).replace(microsecond=0).isoformat().replace('+00:00','Z'))
PY
}

today_date() {
  python3 - <<'PY'
from datetime import datetime, timezone
print(datetime.now(timezone.utc).date().isoformat())
PY
}

json_get() {
  python3 - "$1" "$2" <<'PY'
import json, sys
file_path, key_path = sys.argv[1], sys.argv[2]
try:
    with open(file_path, 'r', encoding='utf-8') as f:
        obj = json.load(f)
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
    if isinstance(obj, (dict, list)):
        print(json.dumps(obj, separators=(',', ':')))
    else:
        print(obj)
except Exception:
    print('')
PY
}

json_pick() {
  local file="$1"
  shift
  local value=""
  for path in "$@"; do
    value="$(json_get "$file" "$path")"
    if [ -n "$value" ] && [ "$value" != "null" ]; then
      printf '%s' "$value"
      return 0
    fi
  done
  printf ''
}

json_status() {
  json_get "$1" "status"
}

jwt_claim() {
  python3 - "$1" "$2" <<'PY'
import base64, json, sys
jwt, claim = sys.argv[1], sys.argv[2]
try:
    payload = jwt.split('.')[1]
    payload += '=' * (-len(payload) % 4)
    obj = json.loads(base64.urlsafe_b64decode(payload.encode()))
    value = obj.get(claim, '')
    if isinstance(value, (dict, list)):
        print(json.dumps(value, separators=(',', ':')))
    else:
        print(value)
except Exception:
    print('')
PY
}

short_body() {
  python3 - "$1" <<'PY'
import json, sys
p = sys.argv[1]
secret_keys = {'access_token','refresh_token','authorization','password','new_password','current_password','token','jwt'}
try:
    data = open(p, 'r', encoding='utf-8').read()
    try:
        obj = json.loads(data)
        def redact(x):
            if isinstance(x, dict):
                return {k: ('<redacted>' if k.lower() in secret_keys else redact(v)) for k, v in x.items()}
            if isinstance(x, list):
                return [redact(i) for i in x]
            return x
        print(json.dumps(redact(obj), indent=2)[:1800])
    except Exception:
        print(data[:1800])
except Exception as e:
    print(f'<unable to read response: {e}>')
PY
}

sanitize_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_'
}

record_pass() {
  TEST_COUNT=$((TEST_COUNT + 1))
  PASS_COUNT=$((PASS_COUNT + 1))
  printf "%s[PASS]%s %s\n" "$GREEN" "$RESET" "$1"
}

record_fail() {
  TEST_COUNT=$((TEST_COUNT + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "%s[FAIL]%s %s\n" "$RED" "$RESET" "$1"
  if [ "${2:-}" != "" ]; then
    echo "       $2"
  fi
}

record_skip() {
  TEST_COUNT=$((TEST_COUNT + 1))
  SKIP_COUNT=$((SKIP_COUNT + 1))
  printf "%s[SKIP]%s %s\n" "$YELLOW" "$RESET" "$1"
  if [ "${2:-}" != "" ]; then
    echo "       $2"
  fi
}

request_to() {
  # request_to <service> <base_url> <forwarded_proto> <name> <method> <path> <expected_codes_regex> <body_or_empty> <bearer_or_empty>
  local service="$1"
  local base_url="$2"
  local forwarded_proto="$3"
  local name="$4"
  local method="$5"
  local path="$6"
  local expected="$7"
  local body="${8:-}"
  local token="${9:-}"
  local key outfile req_id trace_id http_code curl_exit

  key="$(sanitize_name "${service}_${name}")"
  outfile="$TMP_DIR/${key}.json"
  req_id="req-$(new_uuid)"
  trace_id="$(new_uuid | tr -d '-')"

  if [ -z "$base_url" ]; then
    record_skip "$service $name" "base URL not configured"
    return 2
  fi

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

  if [ -n "$forwarded_proto" ]; then
    curl_args+=( -H "X-Forwarded-Proto: $forwarded_proto" )
  fi

  if [ -n "$token" ]; then
    curl_args+=( -H "Authorization: Bearer $token" )
  fi

  if [ -n "$body" ]; then
    curl_args+=( -H "Content-Type: application/json" -d "$body" )
  fi

  http_code="$(curl "${curl_args[@]}" 2>"$outfile.curlerr")"
  curl_exit=$?

  echo "$outfile" > "$TMP_DIR/${key}.path"
  echo "$http_code" > "$TMP_DIR/${key}.code"

  if [ "$VERBOSE" = "1" ]; then
    echo "--- [$service] $name response ($http_code) ---"
    short_body "$outfile"
    echo "----------------------------------------"
  fi

  if [ "$curl_exit" -ne 0 ]; then
    record_fail "$service $name" "curl failed: $(cat "$outfile.curlerr")"
    return 1
  fi

  if printf '%s' "$http_code" | grep -Eq "^($expected)$"; then
    record_pass "$service $name ($method $path -> HTTP $http_code)"
    return 0
  fi

  record_fail "$service $name ($method $path expected HTTP $expected but got $http_code)" "response: $(short_body "$outfile" | tr '\n' ' ' | cut -c1-1000)"
  return 1
}

request_todo() {
  request_to "todo" "$TODO_BASE_URL" "$TODO_FORWARDED_PROTO" "$@"
}

request_auth() {
  request_to "auth" "$AUTH_BASE_URL" "$AUTH_FORWARDED_PROTO" "$@"
}

request_admin() {
  request_to "admin" "$ADMIN_BASE_URL" "$ADMIN_FORWARDED_PROTO" "$@"
}

request_user() {
  request_to "user" "$USER_BASE_URL" "$USER_FORWARDED_PROTO" "$@"
}

request_report() {
  request_to "report" "$REPORT_BASE_URL" "$REPORT_FORWARDED_PROTO" "$@"
}

last_file() {
  local key
  key="$(sanitize_name "${1}_${2}")"
  cat "$TMP_DIR/${key}.path" 2>/dev/null || true
}

assert_json_status_ok() {
  local service="$1"
  local name="$2"
  local file
  file="$(last_file "$service" "$name")"
  if [ -z "$file" ]; then
    record_fail "$service $name envelope status" "response file missing"
    return 1
  fi
  if [ "$(json_status "$file")" = "ok" ]; then
    record_pass "$service $name envelope status is ok"
  else
    record_fail "$service $name envelope status" "expected status=ok; body: $(short_body "$file" | tr '\n' ' ' | cut -c1-800)"
  fi
}

print_header() {
  echo "${BOLD}${BLUE}Todo Service Full API + Integration Test${RESET}"
  echo "Todo Base URL:   $TODO_BASE_URL"
  echo "Auth Base URL:   $AUTH_BASE_URL"
  echo "Admin Base URL:  ${ADMIN_BASE_URL:-<disabled>}"
  echo "User Base URL:   ${USER_BASE_URL:-<disabled>}"
  echo "Report Base URL: ${REPORT_BASE_URL:-<disabled>}"
  echo "Tenant:          $TENANT"
  echo "Timeout:         ${TIMEOUT}s"
  echo "Run ID:          $RUN_ID"
  echo
}

signup_user() {
  local username="$1"
  local email="$2"
  local password="$3"
  local label="$4"
  local body file access refresh user_id
  body=$(cat <<JSON
{
  "username": "$username",
  "email": "$email",
  "password": "$password",
  "full_name": "Todo Test User $label",
  "birthdate": "1998-05-20",
  "gender": "male",
  "account_type": "user"
}
JSON
)
  request_auth "signup $label" "POST" "/v1/signup" "200|201" "$body" ""
  file="$(last_file auth "signup $label")"
  access="$(json_pick "$file" "data.tokens.access_token" "data.access_token" "access_token")"
  refresh="$(json_pick "$file" "data.tokens.refresh_token" "data.refresh_token" "refresh_token")"
  user_id="$(json_pick "$file" "data.user.id" "data.user.user_id" "data.id" "user.id" "id")"
  if [ -n "$access" ] && [ -n "$user_id" ]; then
    record_pass "auth signup $label returned access token and user id"
  else
    record_fail "auth signup $label returned access token and user id" "missing token or user id; body: $(short_body "$file" | tr '\n' ' ' | cut -c1-800)"
  fi
  printf '%s|%s|%s' "$access" "$refresh" "$user_id"
}

signin_user() {
  local username="$1"
  local password="$2"
  local label="$3"
  local body file access refresh user_id role admin_status
  body=$(cat <<JSON
{
  "username_or_email": "$username",
  "password": "$password",
  "device_id": "todo-full-api-test-$RUN_ID"
}
JSON
)
  request_auth "signin $label" "POST" "/v1/signin" "200" "$body" ""
  file="$(last_file auth "signin $label")"
  access="$(json_pick "$file" "data.tokens.access_token" "data.access_token" "access_token")"
  refresh="$(json_pick "$file" "data.tokens.refresh_token" "data.refresh_token" "refresh_token")"
  user_id="$(json_pick "$file" "data.user.id" "data.user.user_id" "data.id" "user.id" "id")"
  role="$(json_pick "$file" "data.user.role" "user.role" "role")"
  admin_status="$(json_pick "$file" "data.user.admin_status" "user.admin_status" "admin_status")"
  printf '%s|%s|%s|%s|%s' "$access" "$refresh" "$user_id" "$role" "$admin_status"
}

extract_todo_id_from_file() {
  local file="$1"
  json_pick "$file" \
    "data.todo.id" \
    "data.todo.todo_id" \
    "data.id" \
    "data.todoId" \
    "data.todo_id" \
    "todo.id" \
    "todo.todo_id" \
    "id" \
    "todo_id"
}

create_todo() {
  local label="$1"
  local title="$2"
  local priority="$3"
  local due_date="$4"
  local token="$5"
  local body file todo_id
  body=$(cat <<JSON
{
  "title": "$title",
  "description": "Created by todo_service_full_api_test.sh run $RUN_ID for $label",
  "priority": "$priority",
  "due_date": "$due_date",
  "tags": ["smoke-test", "todo-service", "$label"]
}
JSON
)
  request_todo "create todo $label" "POST" "/v1/todos" "200|201" "$body" "$token"
  file="$(last_file todo "create todo $label")"
  todo_id="$(extract_todo_id_from_file "$file")"
  if [ -n "$todo_id" ]; then
    record_pass "todo create $label returned todo id: $todo_id"
  else
    record_fail "todo create $label returned todo id" "body: $(short_body "$file" | tr '\n' ' ' | cut -c1-900)"
  fi
  printf '%s' "$todo_id"
}

maybe_sleep_for_events() {
  if [ "$RUN_DOWNSTREAM" = "1" ] && [ "$EVENT_WAIT_SECONDS" -gt 0 ] 2>/dev/null; then
    echo "Waiting ${EVENT_WAIT_SECONDS}s for Kafka projections..."
    sleep "$EVENT_WAIT_SECONDS"
  fi
}

select_report_type() {
  local token="$1"
  local file selected
  if [ -n "$REPORT_TYPE" ]; then
    printf '%s' "$REPORT_TYPE"
    return 0
  fi
  request_report "list report types for todo discovery" "GET" "/v1/reports/types" "200" "" "$token" || true
  file="$(last_file report "list report types for todo discovery")"
  selected="$(python3 - "$file" <<'PY'
import json, sys
p = sys.argv[1]
try:
    data = json.load(open(p, encoding='utf-8'))
except Exception:
    print('')
    raise SystemExit
items = data.get('data', data)
# Flatten common shapes: list, dict with types/items/report_types, dict keyed by type.
candidates = []
if isinstance(items, dict):
    for key in ('types','items','report_types','reports'):
        if isinstance(items.get(key), list):
            candidates.extend(items[key])
    for k, v in items.items():
        if isinstance(v, dict):
            vv = dict(v)
            vv.setdefault('report_type', k)
            candidates.append(vv)
elif isinstance(items, list):
    candidates = items
for item in candidates:
    if isinstance(item, str):
        value = item
    elif isinstance(item, dict):
        value = item.get('report_type') or item.get('type') or item.get('name') or item.get('id') or ''
    else:
        value = ''
    if 'todo' in value.lower():
        print(value)
        raise SystemExit
print('')
PY
)"
  printf '%s' "$selected"
}

print_header

# ------------------------------------------------------------------------------
# Public system API and rejected routes
# ------------------------------------------------------------------------------
request_todo "hello" "GET" "/hello" "200" "" ""
assert_json_status_ok "todo" "hello"
request_todo "health" "GET" "/health" "200|503" "" ""
request_todo "docs" "GET" "/docs" "200" "" ""
request_todo "root rejected" "GET" "/" "404" "" ""
request_todo "live rejected" "GET" "/live" "404" "" ""
request_todo "ready rejected" "GET" "/ready" "404" "" ""
request_todo "healthy rejected" "GET" "/healthy" "404" "" ""
request_todo "openapi json rejected" "GET" "/openapi.json" "401|404" "" ""

# ------------------------------------------------------------------------------
# Authentication setup
# ------------------------------------------------------------------------------
PRIMARY_SIGNUP_RESULT="$(signup_user "$PRIMARY_USERNAME" "$PRIMARY_EMAIL" "$USER_PASSWORD" "primary")"
PRIMARY_ACCESS_TOKEN="$(printf '%s' "$PRIMARY_SIGNUP_RESULT" | cut -d'|' -f1)"
PRIMARY_REFRESH_TOKEN="$(printf '%s' "$PRIMARY_SIGNUP_RESULT" | cut -d'|' -f2)"
PRIMARY_USER_ID="$(printf '%s' "$PRIMARY_SIGNUP_RESULT" | cut -d'|' -f3)"

PRIMARY_SIGNIN_RESULT="$(signin_user "$PRIMARY_USERNAME" "$USER_PASSWORD" "primary")"
SIGNED_IN_ACCESS_TOKEN="$(printf '%s' "$PRIMARY_SIGNIN_RESULT" | cut -d'|' -f1)"
SIGNED_IN_USER_ID="$(printf '%s' "$PRIMARY_SIGNIN_RESULT" | cut -d'|' -f3)"
if [ -n "$SIGNED_IN_ACCESS_TOKEN" ]; then PRIMARY_ACCESS_TOKEN="$SIGNED_IN_ACCESS_TOKEN"; fi
if [ -n "$SIGNED_IN_USER_ID" ]; then PRIMARY_USER_ID="$SIGNED_IN_USER_ID"; fi

SECOND_SIGNUP_RESULT="$(signup_user "$SECOND_USERNAME" "$SECOND_EMAIL" "$SECOND_USER_PASSWORD" "second")"
SECOND_ACCESS_TOKEN="$(printf '%s' "$SECOND_SIGNUP_RESULT" | cut -d'|' -f1)"
SECOND_USER_ID="$(printf '%s' "$SECOND_SIGNUP_RESULT" | cut -d'|' -f3)"

ADMIN_SIGNIN_RESULT="$(signin_user "$AUTH_ADMIN_USERNAME" "$AUTH_ADMIN_PASSWORD" "bootstrap admin")"
ADMIN_ACCESS_TOKEN="$(printf '%s' "$ADMIN_SIGNIN_RESULT" | cut -d'|' -f1)"
ADMIN_USER_ID="$(printf '%s' "$ADMIN_SIGNIN_RESULT" | cut -d'|' -f3)"
ADMIN_ROLE="$(printf '%s' "$ADMIN_SIGNIN_RESULT" | cut -d'|' -f4)"
ADMIN_STATUS="$(printf '%s' "$ADMIN_SIGNIN_RESULT" | cut -d'|' -f5)"

if [ -n "$PRIMARY_ACCESS_TOKEN" ]; then
  CLAIM_TENANT="$(jwt_claim "$PRIMARY_ACCESS_TOKEN" tenant)"
  CLAIM_ROLE="$(jwt_claim "$PRIMARY_ACCESS_TOKEN" role)"
  CLAIM_ISS="$(jwt_claim "$PRIMARY_ACCESS_TOKEN" iss)"
  CLAIM_AUD="$(jwt_claim "$PRIMARY_ACCESS_TOKEN" aud)"
  if [ "$CLAIM_ROLE" = "user" ] && [ "$CLAIM_ISS" = "auth" ] && [ "$CLAIM_AUD" = "micro-app" ]; then
    record_pass "primary JWT has expected iss/aud/role"
  else
    record_fail "primary JWT has expected iss/aud/role" "iss=$CLAIM_ISS aud=$CLAIM_AUD role=$CLAIM_ROLE tenant=$CLAIM_TENANT"
  fi
else
  record_fail "primary access token available" "auth setup failed"
fi

if [ -n "$ADMIN_ACCESS_TOKEN" ] && [ "$ADMIN_ROLE" = "admin" ] && [ "$ADMIN_STATUS" = "approved" ]; then
  record_pass "bootstrap admin token is approved admin"
else
  record_skip "bootstrap admin token is approved admin" "admin signin failed or not approved: role=$ADMIN_ROLE admin_status=$ADMIN_STATUS"
fi

# ------------------------------------------------------------------------------
# Auth protection checks
# ------------------------------------------------------------------------------
request_todo "list without token" "GET" "/v1/todos" "401" "" ""
request_todo "list with invalid token" "GET" "/v1/todos" "401" "" "not-a-valid-jwt"

# ------------------------------------------------------------------------------
# Todo API valid flows
# ------------------------------------------------------------------------------
DUE_TOMORROW="$(iso_datetime_days_from_now 1)"
DUE_TODAY="$(iso_datetime_days_from_now 0)"
DUE_YESTERDAY="$(iso_datetime_days_from_now -1)"
TODO_MAIN_ID=""
TODO_TODAY_ID=""
TODO_OVERDUE_ID=""
TODO_HARD_ID=""

if [ -n "$PRIMARY_ACCESS_TOKEN" ]; then
  TODO_MAIN_ID="$(create_todo "main" "Main todo $RUN_ID" "HIGH" "$DUE_TOMORROW" "$PRIMARY_ACCESS_TOKEN")"
  TODO_TODAY_ID="$(create_todo "today" "Today todo $RUN_ID" "MEDIUM" "$DUE_TODAY" "$PRIMARY_ACCESS_TOKEN")"
  TODO_OVERDUE_ID="$(create_todo "overdue" "Overdue todo $RUN_ID" "URGENT" "$DUE_YESTERDAY" "$PRIMARY_ACCESS_TOKEN")"
  TODO_HARD_ID="$(create_todo "hard-delete" "Hard delete todo $RUN_ID" "LOW" "$DUE_TOMORROW" "$PRIMARY_ACCESS_TOKEN")"

  request_todo "list own todos" "GET" "/v1/todos" "200" "" "$PRIMARY_ACCESS_TOKEN"
  request_todo "list own todos filtered" "GET" "/v1/todos?status=PENDING&priority=HIGH" "200" "" "$PRIMARY_ACCESS_TOKEN"
  request_todo "list today todos" "GET" "/v1/todos/today" "200" "" "$PRIMARY_ACCESS_TOKEN"
  request_todo "list overdue todos" "GET" "/v1/todos/overdue" "200" "" "$PRIMARY_ACCESS_TOKEN"

  if [ -n "$TODO_MAIN_ID" ]; then
    request_todo "get todo" "GET" "/v1/todos/$TODO_MAIN_ID" "200" "" "$PRIMARY_ACCESS_TOKEN"

    UPDATE_BODY=$(cat <<JSON
{
  "title": "Updated main todo $RUN_ID",
  "description": "Updated by full API test",
  "priority": "URGENT",
  "due_date": "$DUE_TOMORROW",
  "tags": ["smoke-test", "updated"]
}
JSON
)
    request_todo "update todo" "PUT" "/v1/todos/$TODO_MAIN_ID" "200" "$UPDATE_BODY" "$PRIMARY_ACCESS_TOKEN"

    STATUS_BODY=$(cat <<JSON
{
  "status": "IN_PROGRESS"
}
JSON
)
    request_todo "change status in progress" "PATCH" "/v1/todos/$TODO_MAIN_ID/status" "200" "$STATUS_BODY" "$PRIMARY_ACCESS_TOKEN"
    request_todo "todo history after update" "GET" "/v1/todos/$TODO_MAIN_ID/history" "200" "" "$PRIMARY_ACCESS_TOKEN"
    request_todo "complete todo" "POST" "/v1/todos/$TODO_MAIN_ID/complete" "200" "" "$PRIMARY_ACCESS_TOKEN"
    request_todo "archive todo" "POST" "/v1/todos/$TODO_MAIN_ID/archive" "200" "" "$PRIMARY_ACCESS_TOKEN"
    request_todo "restore todo" "POST" "/v1/todos/$TODO_MAIN_ID/restore" "200" "" "$PRIMARY_ACCESS_TOKEN"
  else
    record_skip "get/update/status/history/complete/archive/restore" "main todo id missing"
  fi
else
  record_fail "primary access token for todo tests" "cannot run todo APIs without a user token"
fi

# ------------------------------------------------------------------------------
# Todo API invalid inputs
# ------------------------------------------------------------------------------
if [ -n "$PRIMARY_ACCESS_TOKEN" ]; then
  INVALID_CREATE_BODY=$(cat <<JSON
{
  "title": "",
  "description": "invalid empty title",
  "priority": "HIGH",
  "due_date": "$DUE_TOMORROW",
  "tags": ["invalid"]
}
JSON
)
  request_todo "create invalid empty title" "POST" "/v1/todos" "400|422" "$INVALID_CREATE_BODY" "$PRIMARY_ACCESS_TOKEN"

  INVALID_PRIORITY_BODY=$(cat <<JSON
{
  "title": "Invalid priority todo $RUN_ID",
  "description": "invalid priority",
  "priority": "CRITICAL_INVALID",
  "due_date": "$DUE_TOMORROW",
  "tags": ["invalid"]
}
JSON
)
  request_todo "create invalid priority" "POST" "/v1/todos" "400|422" "$INVALID_PRIORITY_BODY" "$PRIMARY_ACCESS_TOKEN"
  request_todo "create malformed json" "POST" "/v1/todos" "400|422" '{"title": "broken",' "$PRIMARY_ACCESS_TOKEN"
  request_todo "get missing todo" "GET" "/v1/todos/missing-todo-$RUN_ID" "404" "" "$PRIMARY_ACCESS_TOKEN"

  if [ -n "$TODO_MAIN_ID" ]; then
    INVALID_STATUS_BODY=$(cat <<JSON
{
  "status": "NOT_A_STATUS"
}
JSON
)
    request_todo "invalid status transition" "PATCH" "/v1/todos/$TODO_MAIN_ID/status" "400|422" "$INVALID_STATUS_BODY" "$PRIMARY_ACCESS_TOKEN"
  else
    record_skip "invalid status transition" "main todo id missing"
  fi

  if [ -n "$TODO_HARD_ID" ]; then
    request_todo "normal user hard delete forbidden" "DELETE" "/v1/todos/$TODO_HARD_ID/hard" "403" "" "$PRIMARY_ACCESS_TOKEN"
  else
    record_skip "normal user hard delete forbidden" "hard-delete todo id missing"
  fi
fi

# ------------------------------------------------------------------------------
# Soft delete and hard delete mutation checks
# ------------------------------------------------------------------------------
if [ "$RUN_MUTATIONS" = "1" ] && [ -n "$PRIMARY_ACCESS_TOKEN" ]; then
  DELETE_ID="$(create_todo "soft-delete" "Soft delete todo $RUN_ID" "LOW" "$DUE_TOMORROW" "$PRIMARY_ACCESS_TOKEN")"
  if [ -n "$DELETE_ID" ]; then
    request_todo "soft delete todo" "DELETE" "/v1/todos/$DELETE_ID" "200|204" "" "$PRIMARY_ACCESS_TOKEN"
    request_todo "restore soft deleted todo" "POST" "/v1/todos/$DELETE_ID/restore" "200" "" "$PRIMARY_ACCESS_TOKEN"
  else
    record_skip "soft delete todo" "soft-delete todo id missing"
    record_skip "restore soft deleted todo" "soft-delete todo id missing"
  fi
else
  record_skip "soft delete todo" "TODO_TEST_RUN_MUTATIONS disabled or no token"
  record_skip "restore soft deleted todo" "TODO_TEST_RUN_MUTATIONS disabled or no token"
fi

if [ "$RUN_MUTATIONS" = "1" ] && [ -n "$ADMIN_ACCESS_TOKEN" ] && [ -n "$TODO_HARD_ID" ]; then
  request_todo "admin hard delete todo" "DELETE" "/v1/todos/$TODO_HARD_ID/hard" "200|204" "" "$ADMIN_ACCESS_TOKEN"
else
  record_skip "admin hard delete todo" "mutation disabled, admin token missing, or hard-delete todo id missing"
fi

maybe_sleep_for_events

# ------------------------------------------------------------------------------
# Optional downstream projection/integration checks
# ------------------------------------------------------------------------------
if [ "$RUN_DOWNSTREAM" = "1" ]; then
  if [ -n "$ADMIN_BASE_URL" ] && [ -n "$ADMIN_ACCESS_TOKEN" ]; then
    request_admin "admin dashboard" "GET" "/v1/admin/dashboard" "200" "" "$ADMIN_ACCESS_TOKEN"
    request_admin "admin todo summary" "GET" "/v1/admin/todos/summary" "200" "" "$ADMIN_ACCESS_TOKEN"
    request_admin "admin todo projections" "GET" "/v1/admin/todos" "200" "" "$ADMIN_ACCESS_TOKEN"
    if [ -n "$PRIMARY_USER_ID" ]; then
      request_admin "admin user todo projections" "GET" "/v1/admin/todos/users/$PRIMARY_USER_ID" "200" "" "$ADMIN_ACCESS_TOKEN"
    else
      record_skip "admin user todo projections" "primary user id missing"
    fi
    if [ -n "$TODO_MAIN_ID" ]; then
      request_admin "admin todo projection detail" "GET" "/v1/admin/todos/$TODO_MAIN_ID" "200|404" "" "$ADMIN_ACCESS_TOKEN"
    else
      record_skip "admin todo projection detail" "main todo id missing"
    fi
  else
    record_skip "admin downstream todo checks" "ADMIN_BASE_URL or admin token missing"
  fi

  if [ -n "$USER_BASE_URL" ] && [ -n "$PRIMARY_ACCESS_TOKEN" ]; then
    request_user "current profile" "GET" "/v1/users/me" "200" "" "$PRIMARY_ACCESS_TOKEN"
    request_user "own todo projections" "GET" "/v1/users/me/todos" "200" "" "$PRIMARY_ACCESS_TOKEN"
    request_user "own todo summary" "GET" "/v1/users/me/todos/summary" "200" "" "$PRIMARY_ACCESS_TOKEN"
    request_user "own todo activity" "GET" "/v1/users/me/todos/activity" "200" "" "$PRIMARY_ACCESS_TOKEN"
    if [ -n "$TODO_MAIN_ID" ]; then
      request_user "own todo projection detail" "GET" "/v1/users/me/todos/$TODO_MAIN_ID" "200|404" "" "$PRIMARY_ACCESS_TOKEN"
    else
      record_skip "own todo projection detail" "main todo id missing"
    fi
    if [ -n "$SECOND_USER_ID" ]; then
      request_user "cross user todo without grant forbidden" "GET" "/v1/users/$SECOND_USER_ID/todos" "403|404" "" "$PRIMARY_ACCESS_TOKEN"
    else
      record_skip "cross user todo without grant forbidden" "second user id missing"
    fi
  else
    record_skip "user downstream todo checks" "USER_BASE_URL or primary token missing"
  fi

  if [ -n "$REPORT_BASE_URL" ] && [ -n "$PRIMARY_ACCESS_TOKEN" ]; then
    SELECTED_REPORT_TYPE="$(select_report_type "$PRIMARY_ACCESS_TOKEN")"
    if [ -n "$SELECTED_REPORT_TYPE" ]; then
      DATE_FROM="$(today_date)"
      DATE_TO="$(today_date)"
      REPORT_BODY=$(cat <<JSON
{
  "report_type": "$SELECTED_REPORT_TYPE",
  "target_user_id": "$PRIMARY_USER_ID",
  "format": "$REPORT_FORMAT",
  "date_from": "$DATE_FROM",
  "date_to": "$DATE_TO",
  "filters": {"resource_type": "todo"},
  "options": {"source": "todo_service_full_api_test"}
}
JSON
)
      request_report "request todo report" "POST" "/v1/reports" "200|201|202" "$REPORT_BODY" "$PRIMARY_ACCESS_TOKEN"
      REPORT_FILE="$(last_file report "request todo report")"
      REPORT_ID="$(json_pick "$REPORT_FILE" "data.report.id" "data.report.report_id" "data.id" "data.report_id" "report.id" "id")"
      if [ -n "$REPORT_ID" ]; then
        request_report "get requested todo report" "GET" "/v1/reports/$REPORT_ID" "200" "" "$PRIMARY_ACCESS_TOKEN"
      else
        record_skip "get requested todo report" "report id missing"
      fi
    else
      record_skip "request todo report" "no todo report type found; set TODO_TEST_REPORT_TYPE in env"
    fi
  else
    record_skip "report downstream todo checks" "REPORT_BASE_URL or primary token missing"
  fi
else
  record_skip "downstream integration checks" "TODO_TEST_RUN_DOWNSTREAM=0"
fi

# ------------------------------------------------------------------------------
# Final health
# ------------------------------------------------------------------------------
request_todo "health final" "GET" "/health" "200|503" "" ""

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo
printf "%sSummary:%s %s total, %s passed, %s failed, %s skipped\n" "$BOLD" "$RESET" "$TEST_COUNT" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
echo "Primary user:  $PRIMARY_USERNAME / $PRIMARY_EMAIL / id=${PRIMARY_USER_ID:-<missing>}"
echo "Second user:   $SECOND_USERNAME / $SECOND_EMAIL / id=${SECOND_USER_ID:-<missing>}"
echo "Main todo id:  ${TODO_MAIN_ID:-<missing>}"
echo "Today todo id: ${TODO_TODAY_ID:-<missing>}"
echo "Overdue id:    ${TODO_OVERDUE_ID:-<missing>}"
echo "Todo URL:      $TODO_BASE_URL"
echo "Auth URL:      $AUTH_BASE_URL"

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo
  echo "One or more todo service checks failed. Review the failure messages above."
  exit 1
fi

echo
printf "%sAll required todo service checks passed.%s\n" "$GREEN" "$RESET"
exit 0
