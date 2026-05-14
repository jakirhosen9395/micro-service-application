#!/usr/bin/env bash
# Admin Service API smoke/contract test script.
#
# Usage:
#   chmod +x admin_service_api_smoke_test.sh
#   ./admin_service_api_smoke_test.sh <admin-ip-or-url> <auth-ip-or-url>
#   ./admin_service_api_smoke_test.sh <admin-ip> <admin-port> <auth-ip> <auth-port>
#
# Examples:
#   ./admin_service_api_smoke_test.sh 192.168.56.100 1010 192.168.56.100 6060
#   ./admin_service_api_smoke_test.sh http://52.66.223.53:1010 http://52.66.223.53:6060
#
# Optional environment variables:
#   ADMIN_TEST_AUTH_USERNAME=admin
#   ADMIN_TEST_AUTH_PASSWORD=admin123
#   ADMIN_TEST_AUTH_LOGIN_PATH=/v1/signin
#   ADMIN_TEST_TIMEOUT=20
#   ADMIN_TEST_VERBOSE=1
#   ADMIN_TEST_CREATE_NORMAL_USER=1
#   ADMIN_TEST_MUTATE=0
#   ADMIN_TEST_REPORT_TARGET_USER_ID=<target-user-id>
#   ADMIN_TEST_SAVE_RESPONSES=0
#
# Safe by default:
#   - GET endpoints are tested with real IDs when discovered.
#   - Mutation endpoints are called with fake IDs and expected to return 404.
#   - Set ADMIN_TEST_MUTATE=1 to exercise mutations with discovered IDs when possible.

set -u

usage() {
  cat <<'USAGE'
Usage:
  ./admin_service_api_smoke_test.sh <admin-ip-or-url> <auth-ip-or-url>
  ./admin_service_api_smoke_test.sh <admin-ip> <admin-port> <auth-ip> <auth-port>

Examples:
  ./admin_service_api_smoke_test.sh 192.168.56.100 1010 192.168.56.100 6060
  ./admin_service_api_smoke_test.sh http://52.66.223.53:1010 http://52.66.223.53:6060

Optional environment variables:
  ADMIN_TEST_AUTH_USERNAME=admin
  ADMIN_TEST_AUTH_PASSWORD=admin123
  ADMIN_TEST_AUTH_LOGIN_PATH=/v1/signin
  ADMIN_TEST_TIMEOUT=20
  ADMIN_TEST_VERBOSE=1
  ADMIN_TEST_CREATE_NORMAL_USER=1
  ADMIN_TEST_MUTATE=0
  ADMIN_TEST_REPORT_TARGET_USER_ID=<target-user-id>
  ADMIN_TEST_SAVE_RESPONSES=0
USAGE
}

normalize_base_url() {
  local input="$1"
  local port="$2"
  if printf '%s' "$input" | grep -Eq '^https?://'; then
    printf '%s' "${input%/}"
  else
    printf 'http://%s:%s' "$input" "$port"
  fi
}

if [ "$#" -eq 2 ]; then
  ADMIN_BASE_URL="$(normalize_base_url "$1" 1010)"
  AUTH_BASE_URL="$(normalize_base_url "$2" 6060)"
elif [ "$#" -eq 3 ]; then
  ADMIN_BASE_URL="$(normalize_base_url "$1" "$2")"
  AUTH_BASE_URL="$(normalize_base_url "$3" 6060)"
elif [ "$#" -ge 4 ]; then
  ADMIN_BASE_URL="$(normalize_base_url "$1" "$2")"
  AUTH_BASE_URL="$(normalize_base_url "$3" "$4")"
else
  usage
  exit 2
fi

TIMEOUT="${ADMIN_TEST_TIMEOUT:-20}"
VERBOSE="${ADMIN_TEST_VERBOSE:-0}"
CREATE_NORMAL_USER="${ADMIN_TEST_CREATE_NORMAL_USER:-1}"
MUTATE="${ADMIN_TEST_MUTATE:-0}"
SAVE_RESPONSES="${ADMIN_TEST_SAVE_RESPONSES:-0}"
AUTH_LOGIN_PATH="${ADMIN_TEST_AUTH_LOGIN_PATH:-/v1/signin}"
ADMIN_USERNAME="${ADMIN_TEST_AUTH_USERNAME:-admin}"
ADMIN_PASSWORD="${ADMIN_TEST_AUTH_PASSWORD:-admin123}"
RUN_ID="$(date +%s)-$RANDOM"

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
ADMIN_TOKEN=""
NORMAL_TOKEN=""
FIRST_USER_ID=""
REGISTRATION_ID=""
ACCESS_REQUEST_ID=""
ACCESS_GRANT_ID=""
CALCULATION_ID=""
TODO_ID=""
REPORT_ID=""
AUDIT_EVENT_ID=""

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

json_get() {
  python3 - "$1" "$2" <<'PY'
import json, sys
file_path, key_path = sys.argv[1], sys.argv[2]
try:
    with open(file_path, 'r', encoding='utf-8') as f:
        raw = f.read()
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
  local file="$1"
  shift
  local value=""
  local path
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
        sensitive = {
            'access_token', 'refresh_token', 'authorization', 'password',
            'new_password', 'current_password', 'token', 'jwt', 'secret'
        }
        def redact(x):
            if isinstance(x, dict):
                out = {}
                for k, v in x.items():
                    if k.lower() in sensitive or 'token' in k.lower() or 'secret' in k.lower() or 'password' in k.lower():
                        out[k] = '<redacted>'
                    else:
                        out[k] = redact(v)
                return out
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

last_file() {
  cat "$TMP_DIR/${1//[^A-Za-z0-9_]/_}.path" 2>/dev/null || true
}

last_code() {
  cat "$TMP_DIR/${1//[^A-Za-z0-9_]/_}.code" 2>/dev/null || true
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
  local outfile="$TMP_DIR/${name//[^A-Za-z0-9_]/_}.json"
  local req_id="req-$(new_uuid | tr -d '-')"
  local trace_id="$req_id"
  local http_code curl_exit

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

  if [ "$token" != "" ]; then
    curl_args+=( -H "Authorization: Bearer $token" )
  fi

  if [ "$body" != "" ]; then
    curl_args+=( -H "Content-Type: application/json" -d "$body" )
  fi

  http_code="$(curl "${curl_args[@]}" 2>"$outfile.curlerr")"
  curl_exit=$?

  echo "$outfile" > "$TMP_DIR/${name//[^A-Za-z0-9_]/_}.path"
  echo "$http_code" > "$TMP_DIR/${name//[^A-Za-z0-9_]/_}.code"

  if [ "$VERBOSE" = "1" ]; then
    echo "--- $name response ($http_code) ---"
    short_body "$outfile"
    echo "-------------------------------"
  fi

  if [ "$curl_exit" -ne 0 ]; then
    record_fail "$name" "curl failed: $(cat "$outfile.curlerr")"
    return 1
  fi

  if printf '%s' "$http_code" | grep -Eq "^($expected)$"; then
    record_pass "$name ($method $path -> HTTP $http_code)"
    return 0
  fi

  record_fail "$name ($method $path expected HTTP $expected but got $http_code)" "response: $(short_body "$outfile" | tr '\n' ' ' | cut -c1-1000)"
  return 1
}

admin_request() {
  request_base "$ADMIN_BASE_URL" "$@"
}

auth_request() {
  request_base "$AUTH_BASE_URL" "$@"
}

print_header() {
  echo "${BOLD}${BLUE}Admin Service API Smoke Test${RESET}"
  echo "Admin Base URL: $ADMIN_BASE_URL"
  echo "Auth Base URL:  $AUTH_BASE_URL"
  echo "Auth Login:     $AUTH_LOGIN_PATH"
  echo "Timeout:        ${TIMEOUT}s"
  echo "Run ID:         $RUN_ID"
  echo "Safe mutations: $([ "$MUTATE" = "1" ] && echo disabled || echo enabled)"
  echo
}

login_admin() {
  local body
  body=$(cat <<JSON
{
  "username_or_email": "$ADMIN_USERNAME",
  "password": "$ADMIN_PASSWORD",
  "device_id": "admin-service-smoke-$RUN_ID"
}
JSON
)
  auth_request "auth admin signin" "POST" "$AUTH_LOGIN_PATH" "200" "$body" ""
  local file
  file="$(last_file "auth admin signin")"
  ADMIN_TOKEN="$(json_get_any "$file" \
    "data.tokens.access_token" \
    "data.access_token" \
    "access_token" \
    "token")"
  local role admin_status
  role="$(json_get_any "$file" "data.user.role" "user.role" "role")"
  admin_status="$(json_get_any "$file" "data.user.admin_status" "user.admin_status" "admin_status")"
  if [ "$ADMIN_TOKEN" = "" ]; then
    record_fail "auth admin token extracted" "No access token found. Set ADMIN_TEST_AUTH_USERNAME, ADMIN_TEST_AUTH_PASSWORD, or ADMIN_TEST_AUTH_LOGIN_PATH."
    return 1
  fi
  record_pass "auth admin token extracted"
  if [ "$role" = "admin" ] && [ "$admin_status" = "approved" ]; then
    record_pass "auth token belongs to approved admin"
  else
    record_fail "auth token belongs to approved admin" "role=$role admin_status=$admin_status"
  fi
}

create_normal_user_token() {
  if [ "$CREATE_NORMAL_USER" != "1" ]; then
    record_skip "normal user token" "ADMIN_TEST_CREATE_NORMAL_USER is not 1"
    return 0
  fi

  local username="admin_service_normal_${RUN_ID}"
  local email="${username}@example.com"
  local password="Test1234!Aa"
  local body
  body=$(cat <<JSON
{
  "username": "$username",
  "email": "$email",
  "password": "$password",
  "full_name": "Admin Service Smoke Normal User",
  "birthdate": "1998-05-20",
  "gender": "male",
  "account_type": "user"
}
JSON
)
  auth_request "auth signup normal user" "POST" "/v1/signup" "200|201|409" "$body" ""
  local code file signin_body
  code="$(last_code "auth signup normal user")"
  if [ "$code" = "409" ]; then
    record_skip "normal user signup" "username/email collision; continuing with signin attempt"
  fi

  signin_body=$(cat <<JSON
{
  "username_or_email": "$username",
  "password": "$password",
  "device_id": "admin-service-smoke-normal-$RUN_ID"
}
JSON
)
  auth_request "auth normal user signin" "POST" "$AUTH_LOGIN_PATH" "200|401" "$signin_body" ""
  file="$(last_file "auth normal user signin")"
  NORMAL_TOKEN="$(json_get_any "$file" \
    "data.tokens.access_token" \
    "data.access_token" \
    "access_token" \
    "token")"
  if [ "$NORMAL_TOKEN" = "" ]; then
    record_skip "normal user token extracted" "normal user signin did not return a token"
  else
    record_pass "normal user token extracted"
  fi
}

assert_json_status_ok() {
  local name="$1"
  local file
  file="$(last_file "$name")"
  if [ -z "$file" ]; then
    record_fail "$name JSON status" "response file not found"
    return 1
  fi
  local status
  status="$(json_status "$file")"
  if [ "$status" = "ok" ]; then
    record_pass "$name envelope status is ok"
  else
    record_fail "$name envelope status" "expected status=ok, got '$status'. Body: $(short_body "$file" | tr '\n' ' ' | cut -c1-700)"
  fi
}

require_admin_token_or_exit() {
  if [ "$ADMIN_TOKEN" = "" ]; then
    echo
    echo "Cannot continue protected admin API checks because no admin token was obtained."
    exit 1
  fi
}

extract_ids_from_lists() {
  local file

  file="$(last_file "admin list users")"
  FIRST_USER_ID="$(json_get_any "$file" "data.items.0.user_id" "data.items.0.id" "items.0.user_id" "items.0.id")"

  file="$(last_file "admin list registrations")"
  REGISTRATION_ID="$(json_get_any "$file" "data.items.0.request_id" "data.items.0.id" "items.0.request_id" "items.0.id")"

  file="$(last_file "admin list access requests")"
  ACCESS_REQUEST_ID="$(json_get_any "$file" "data.items.0.request_id" "data.items.0.id" "items.0.request_id" "items.0.id")"

  file="$(last_file "admin list access grants")"
  ACCESS_GRANT_ID="$(json_get_any "$file" "data.items.0.grant_id" "data.items.0.id" "items.0.grant_id" "items.0.id")"

  file="$(last_file "admin list calculations")"
  CALCULATION_ID="$(json_get_any "$file" "data.items.0.calculation_id" "data.items.0.id" "items.0.calculation_id" "items.0.id")"

  file="$(last_file "admin list todos")"
  TODO_ID="$(json_get_any "$file" "data.items.0.todo_id" "data.items.0.id" "items.0.todo_id" "items.0.id")"

  file="$(last_file "admin list reports")"
  REPORT_ID="$(json_get_any "$file" "data.items.0.report_id" "data.items.0.id" "items.0.report_id" "items.0.id")"

  file="$(last_file "admin list audit")"
  AUDIT_EVENT_ID="$(json_get_any "$file" "data.items.0.event_id" "data.items.0.id" "items.0.event_id" "items.0.id")"

  if [ "$FIRST_USER_ID" = "" ]; then FIRST_USER_ID="missing-user-$(new_uuid)"; fi
  if [ "$REGISTRATION_ID" = "" ]; then REGISTRATION_ID="missing-registration-$(new_uuid)"; fi
  if [ "$ACCESS_REQUEST_ID" = "" ]; then ACCESS_REQUEST_ID="missing-access-request-$(new_uuid)"; fi
  if [ "$ACCESS_GRANT_ID" = "" ]; then ACCESS_GRANT_ID="missing-access-grant-$(new_uuid)"; fi
  if [ "$CALCULATION_ID" = "" ]; then CALCULATION_ID="missing-calculation-$(new_uuid)"; fi
  if [ "$TODO_ID" = "" ]; then TODO_ID="missing-todo-$(new_uuid)"; fi
  if [ "$REPORT_ID" = "" ]; then REPORT_ID="missing-report-$(new_uuid)"; fi
  if [ "$AUDIT_EVENT_ID" = "" ]; then AUDIT_EVENT_ID="missing-audit-$(new_uuid)"; fi
}

id_expected() {
  # Return expected status for lookups using an id that may be synthetic.
  case "$1" in
    missing-*) printf '404' ;;
    *) printf '200|404' ;;
  esac
}

mutation_id() {
  # In safe mode force a missing id, so mutation routes are tested without changing data.
  local real_id="$1"
  local prefix="$2"
  if [ "$MUTATE" = "1" ] && [ "$real_id" != "" ] && ! printf '%s' "$real_id" | grep -q '^missing-'; then
    printf '%s' "$real_id"
  else
    printf 'missing-%s-%s' "$prefix" "$(new_uuid)"
  fi
}

mutation_expected() {
  if [ "$MUTATE" = "1" ]; then
    printf '200|201|202|400|404|409|422'
  else
    printf '404|400|409|422'
  fi
}

print_header

# Auth preflight and token setup.
auth_request "auth hello" "GET" "/hello" "200" "" ""
auth_request "auth health" "GET" "/health" "200|503" "" ""
login_admin
create_normal_user_token
require_admin_token_or_exit

# Public admin routes.
admin_request "admin hello" "GET" "/hello" "200" "" ""
assert_json_status_ok "admin hello"
admin_request "admin health" "GET" "/health" "200" "" ""
assert_json_status_ok "admin health"
admin_request "admin docs" "GET" "/docs" "200" "" ""

# Rejected public routes.
admin_request "admin root rejected" "GET" "/" "404" "" ""
admin_request "admin live rejected" "GET" "/live" "404" "" ""
admin_request "admin ready rejected" "GET" "/ready" "404" "" ""
admin_request "admin healthy rejected" "GET" "/healthy" "404" "" ""
admin_request "admin openapi rejected" "GET" "/openapi.json" "404" "" ""
admin_request "admin swagger rejected" "GET" "/swagger" "404" "" ""
admin_request "admin redoc rejected" "GET" "/redoc" "404" "" ""
admin_request "admin swagger index rejected" "GET" "/swagger/index.html" "404" "" ""
admin_request "admin swagger json rejected" "GET" "/swagger/v1/swagger.json" "404" "" ""

# AuthZ checks.
admin_request "admin dashboard without token" "GET" "/v1/admin/dashboard" "401" "" ""
admin_request "admin dashboard invalid token" "GET" "/v1/admin/dashboard" "401" "" "not-a-valid-jwt"
if [ "$NORMAL_TOKEN" != "" ]; then
  admin_request "admin dashboard normal user forbidden" "GET" "/v1/admin/dashboard" "403" "" "$NORMAL_TOKEN"
else
  record_skip "admin dashboard normal user forbidden" "no normal user token available"
fi

# Authorized read/list endpoints.
admin_request "admin dashboard" "GET" "/v1/admin/dashboard" "200" "" "$ADMIN_TOKEN"
admin_request "admin summary" "GET" "/v1/admin/summary" "200" "" "$ADMIN_TOKEN"
admin_request "admin list registrations" "GET" "/v1/admin/registrations" "200" "" "$ADMIN_TOKEN"
admin_request "admin list access requests" "GET" "/v1/admin/access-requests" "200" "" "$ADMIN_TOKEN"
admin_request "admin list access grants" "GET" "/v1/admin/access-grants" "200" "" "$ADMIN_TOKEN"
admin_request "admin list users" "GET" "/v1/admin/users" "200" "" "$ADMIN_TOKEN"
admin_request "admin list calculations" "GET" "/v1/admin/calculations" "200" "" "$ADMIN_TOKEN"
admin_request "admin calculations summary" "GET" "/v1/admin/calculations/summary" "200" "" "$ADMIN_TOKEN"
admin_request "admin list todos" "GET" "/v1/admin/todos" "200" "" "$ADMIN_TOKEN"
admin_request "admin todos summary" "GET" "/v1/admin/todos/summary" "200" "" "$ADMIN_TOKEN"
admin_request "admin list reports" "GET" "/v1/admin/reports" "200" "" "$ADMIN_TOKEN"
admin_request "admin reports summary" "GET" "/v1/admin/reports/summary" "200" "" "$ADMIN_TOKEN"
admin_request "admin list audit" "GET" "/v1/admin/audit" "200" "" "$ADMIN_TOKEN"

extract_ids_from_lists

# Authorized detail endpoints.
admin_request "admin get registration" "GET" "/v1/admin/registrations/$REGISTRATION_ID" "$(id_expected "$REGISTRATION_ID")" "" "$ADMIN_TOKEN"
admin_request "admin get access request" "GET" "/v1/admin/access-requests/$ACCESS_REQUEST_ID" "$(id_expected "$ACCESS_REQUEST_ID")" "" "$ADMIN_TOKEN"
admin_request "admin get access grant" "GET" "/v1/admin/access-grants/$ACCESS_GRANT_ID" "$(id_expected "$ACCESS_GRANT_ID")" "" "$ADMIN_TOKEN"
admin_request "admin get user" "GET" "/v1/admin/users/$FIRST_USER_ID" "$(id_expected "$FIRST_USER_ID")" "" "$ADMIN_TOKEN"
admin_request "admin user activity" "GET" "/v1/admin/users/$FIRST_USER_ID/activity" "200|404" "" "$ADMIN_TOKEN"
admin_request "admin user access grants" "GET" "/v1/admin/users/$FIRST_USER_ID/access-grants" "200|404" "" "$ADMIN_TOKEN"
admin_request "admin user reports" "GET" "/v1/admin/users/$FIRST_USER_ID/reports" "200|404" "" "$ADMIN_TOKEN"
admin_request "admin get calculation" "GET" "/v1/admin/calculations/$CALCULATION_ID" "$(id_expected "$CALCULATION_ID")" "" "$ADMIN_TOKEN"
admin_request "admin user calculations" "GET" "/v1/admin/calculations/users/$FIRST_USER_ID" "200|404" "" "$ADMIN_TOKEN"
admin_request "admin get todo" "GET" "/v1/admin/todos/$TODO_ID" "$(id_expected "$TODO_ID")" "" "$ADMIN_TOKEN"
admin_request "admin user todos" "GET" "/v1/admin/todos/users/$FIRST_USER_ID" "200|404" "" "$ADMIN_TOKEN"
admin_request "admin get report" "GET" "/v1/admin/reports/$REPORT_ID" "$(id_expected "$REPORT_ID")" "" "$ADMIN_TOKEN"
admin_request "admin user reports projection" "GET" "/v1/admin/reports/users/$FIRST_USER_ID" "200|404" "" "$ADMIN_TOKEN"
admin_request "admin get audit" "GET" "/v1/admin/audit/$AUDIT_EVENT_ID" "$(id_expected "$AUDIT_EVENT_ID")" "" "$ADMIN_TOKEN"

# Mutation endpoints. Safe mode uses missing IDs to avoid changing real data.
DECISION_BODY='{"reason":"Verified by admin service smoke test."}'
ACCESS_APPROVAL_BODY=$(cat <<JSON
{
  "scope": "calculator:history:read",
  "expires_at": "2030-01-01T00:00:00Z",
  "reason": "Approved by admin service smoke test."
}
JSON
)
REPORT_TARGET_USER_ID="${ADMIN_TEST_REPORT_TARGET_USER_ID:-$FIRST_USER_ID}"
REPORT_BODY=$(cat <<JSON
{
  "report_type": "admin_activity_report",
  "target_user_id": "$REPORT_TARGET_USER_ID",
  "format": "json",
  "date_from": "2026-05-01",
  "date_to": "2026-05-10",
  "filters": {},
  "options": {}
}
JSON
)

MUT_REG_ID="$(mutation_id "$REGISTRATION_ID" "registration")"
MUT_ACCESS_REQUEST_ID="$(mutation_id "$ACCESS_REQUEST_ID" "access-request")"
MUT_ACCESS_GRANT_ID="$(mutation_id "$ACCESS_GRANT_ID" "access-grant")"
MUT_USER_ID="$(mutation_id "$FIRST_USER_ID" "user")"
MUT_REPORT_ID="$(mutation_id "$REPORT_ID" "report")"

admin_request "admin approve registration" "POST" "/v1/admin/registrations/$MUT_REG_ID/approve" "$(mutation_expected)" "$DECISION_BODY" "$ADMIN_TOKEN"
admin_request "admin reject registration" "POST" "/v1/admin/registrations/$MUT_REG_ID/reject" "$(mutation_expected)" "$DECISION_BODY" "$ADMIN_TOKEN"
admin_request "admin approve access request" "POST" "/v1/admin/access-requests/$MUT_ACCESS_REQUEST_ID/approve" "$(mutation_expected)" "$ACCESS_APPROVAL_BODY" "$ADMIN_TOKEN"
admin_request "admin reject access request" "POST" "/v1/admin/access-requests/$MUT_ACCESS_REQUEST_ID/reject" "$(mutation_expected)" "$DECISION_BODY" "$ADMIN_TOKEN"
admin_request "admin revoke access grant" "POST" "/v1/admin/access-grants/$MUT_ACCESS_GRANT_ID/revoke" "$(mutation_expected)" "$DECISION_BODY" "$ADMIN_TOKEN"
admin_request "admin suspend user" "POST" "/v1/admin/users/$MUT_USER_ID/suspend" "$(mutation_expected)" "$DECISION_BODY" "$ADMIN_TOKEN"
admin_request "admin activate user" "POST" "/v1/admin/users/$MUT_USER_ID/activate" "$(mutation_expected)" "$DECISION_BODY" "$ADMIN_TOKEN"
admin_request "admin force password reset" "POST" "/v1/admin/users/$MUT_USER_ID/force-password-reset" "$(mutation_expected)" "$DECISION_BODY" "$ADMIN_TOKEN"

if [ "$MUTATE" = "1" ]; then
  admin_request "admin create report" "POST" "/v1/admin/reports" "200|201|202|400|409|422" "$REPORT_BODY" "$ADMIN_TOKEN"
else
  admin_request "admin create report safe invalid body" "POST" "/v1/admin/reports" "400|415|422" "" "$ADMIN_TOKEN"
fi
admin_request "admin cancel report" "POST" "/v1/admin/reports/$MUT_REPORT_ID/cancel" "$(mutation_expected)" "$DECISION_BODY" "$ADMIN_TOKEN"

# Final health after all endpoint checks.
admin_request "admin health after api checks" "GET" "/health" "200" "" ""

# Summary.
echo
printf "%sSummary:%s %s total, %s passed, %s failed, %s skipped\n" "$BOLD" "$RESET" "$TEST_COUNT" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
echo "Admin Base URL:       $ADMIN_BASE_URL"
echo "Auth Base URL:        $AUTH_BASE_URL"
echo "Mutation mode:        $MUTATE"
echo "Discovered user id:   $FIRST_USER_ID"
echo "Discovered reg id:    $REGISTRATION_ID"
echo "Discovered grant id:  $ACCESS_GRANT_ID"
echo "Discovered report id: $REPORT_ID"
if [ "$SAVE_RESPONSES" = "1" ]; then
  echo "Response files:       $TMP_DIR"
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo
  echo "One or more admin service checks failed. Review the failure messages above."
  exit 1
fi

echo
printf "%sAll required admin service checks passed.%s\n" "$GREEN" "$RESET"
exit 0



# chmod +x admin_service_api_smoke_test.sh
# ./admin_service_api_smoke_test.sh 192.168.56.100 1010 192.168.56.100 6060
# ./admin_service_api_smoke_test.sh http://52.66.223.53:1010 http://52.66.223.53:6060
# ADMIN_TEST_MUTATE=1 ./admin_service_api_smoke_test.sh 192.168.56.100 1010 192.168.56.100 6060
# ADMIN_TEST_VERBOSE=1 ./admin_service_api_smoke_test.sh 192.168.56.100 1010 192.168.56.100 6060 >> admin_service_api_smoke_test_verbose.log


# ADMIN_TEST_AUTH_USERNAME=admin ADMIN_TEST_AUTH_PASSWORD='admin123' ./admin_service_api_smoke_test.sh 192.168.56.100 1010 192.168.56.100 6060
