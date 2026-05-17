#!/usr/bin/env bash
# User Service full API smoke/contract test script.
#
# Usage:
#   chmod +x user_service_api_full_smoke_test.sh
#   ./user_service_api_full_smoke_test.sh --user-host 192.168.56.100 --user-port 4040 --auth-host 192.168.56.100 --auth-port 6060
#   ./user_service_api_full_smoke_test.sh --user-url http://52.66.197.225:4040 --auth-url http://52.66.197.225:6060
#
# Optional environment variables:
#   USER_TEST_TIMEOUT=20
#   USER_TEST_VERBOSE=0
#   USER_TEST_SAVE_RESPONSES=0
#   USER_TEST_CREATE_USER=1
#   USER_TEST_USERNAME=<existing-user>
#   USER_TEST_PASSWORD=<existing-password>
#   USER_TEST_ACCESS_TOKEN=<preissued-user-jwt>
#   USER_TEST_SECOND_TOKEN=<preissued-second-user-jwt>
#   USER_TEST_AUTH_LOGIN_PATH=/v1/signin
#
# What it verifies:
#   - public system endpoints and rejected non-contract routes
#   - missing/invalid JWT 401 behavior
#   - wrong methods 405 behavior
#   - invalid query strings: limit=abc, limit=0, limit=101, offset=-1
#   - malformed/unknown/missing request bodies
#   - normal profile/preferences/dashboard/activity/security endpoints
#   - projected calculations/todos/reports list/detail endpoints
#   - cross-user forbidden responses without a grant
#   - access request create/read/cancel/conflict flow
#   - report request create/read/metadata/progress/cancel/conflict flow
#   - canonical success/error envelope shape

set -u

usage() {
  cat <<'USAGE'
Usage:
  ./user_service_api_full_smoke_test.sh \
    --user-host <ip> [--user-port 4040] \
    --auth-host <ip> [--auth-port 6060]

  ./user_service_api_full_smoke_test.sh \
    --user-url http://<ip>:4040 \
    --auth-url http://<ip>:6060

Named parameters:
  --user-host <host>                  User service host/IP
  --user-port <port>                  User service host port, default 4040
  --user-url <url>                    User service base URL
  --auth-host <host>                  Auth service host/IP
  --auth-port <port>                  Auth service host port, default 6060
  --auth-url <url>                    Auth service base URL
  --timeout <seconds>                 Curl max-time timeout, default 20
  --verbose                           Print response bodies
  --save-responses                    Keep response files in a temp directory
  -h, --help                          Show this help

Environment variables:
  USER_TEST_USERNAME, USER_TEST_PASSWORD
  USER_TEST_ACCESS_TOKEN, USER_TEST_SECOND_TOKEN
  USER_TEST_AUTH_LOGIN_PATH, USER_TEST_CREATE_USER
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

USER_SERVICE_HOST="${USER_SERVICE_HOST:-}"
USER_SERVICE_PORT="${USER_SERVICE_PORT:-4040}"
USER_SERVICE_URL="${USER_SERVICE_URL:-}"
AUTH_SERVICE_HOST="${AUTH_SERVICE_HOST:-}"
AUTH_SERVICE_PORT="${AUTH_SERVICE_PORT:-6060}"
AUTH_SERVICE_URL="${AUTH_SERVICE_URL:-}"

TIMEOUT="${USER_TEST_TIMEOUT:-20}"
VERBOSE="${USER_TEST_VERBOSE:-0}"
SAVE_RESPONSES="${USER_TEST_SAVE_RESPONSES:-0}"
AUTH_LOGIN_PATH="${USER_TEST_AUTH_LOGIN_PATH:-/v1/signin}"
CREATE_USER="${USER_TEST_CREATE_USER:-1}"
ACCESS_TOKEN="${USER_TEST_ACCESS_TOKEN:-}"
SECOND_TOKEN="${USER_TEST_SECOND_TOKEN:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --user-host) USER_SERVICE_HOST="${2:-}"; shift 2 ;;
    --user-port) USER_SERVICE_PORT="${2:-4040}"; shift 2 ;;
    --user-url) USER_SERVICE_URL="${2:-}"; shift 2 ;;
    --auth-host) AUTH_SERVICE_HOST="${2:-}"; shift 2 ;;
    --auth-port) AUTH_SERVICE_PORT="${2:-6060}"; shift 2 ;;
    --auth-url) AUTH_SERVICE_URL="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-20}"; shift 2 ;;
    --verbose) VERBOSE=1; shift 1 ;;
    --save-responses) SAVE_RESPONSES=1; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

if [ -z "$USER_SERVICE_URL" ]; then
  USER_SERVICE_URL="$(normalize_base_url "$USER_SERVICE_HOST" "$USER_SERVICE_PORT")"
fi
if [ -z "$AUTH_SERVICE_URL" ]; then
  AUTH_SERVICE_URL="$(normalize_base_url "$AUTH_SERVICE_HOST" "$AUTH_SERVICE_PORT")"
fi
if [ -z "$USER_SERVICE_URL" ]; then
  echo "Missing user service input. Use --user-host or --user-url."
  usage
  exit 2
fi
if [ -z "$AUTH_SERVICE_URL" ] && [ -z "$ACCESS_TOKEN" ]; then
  echo "Missing auth service input. Use --auth-host/--auth-url or provide USER_TEST_ACCESS_TOKEN."
  usage
  exit 2
fi

RUN_ID="$(date +%s)-$RANDOM"
TEST_USERNAME="${USER_TEST_USERNAME:-userapi_${RUN_ID}}"
TEST_EMAIL="${TEST_USERNAME}@example.com"
TEST_PASSWORD="${USER_TEST_PASSWORD:-Test1234!Aa}"
SECOND_USERNAME="userapi_other_${RUN_ID}"
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
SECOND_USER_ID=""
ACCESS_REQUEST_ID=""
REPORT_ID=""

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

jwt_sub() {
  python3 - "$1" <<'PY'
import base64, json, sys
try:
    token = sys.argv[1]
    payload = token.split('.')[1]
    payload += '=' * (-len(payload) % 4)
    obj = json.loads(base64.urlsafe_b64decode(payload.encode()))
    print(obj.get('sub') or '')
except Exception:
    print('')
PY
}

future_rfc3339() {
  python3 - "$1" <<'PY'
from datetime import datetime, timezone, timedelta
import sys
days = int(sys.argv[1])
print((datetime.now(timezone.utc) + timedelta(days=days)).replace(microsecond=0).isoformat().replace('+00:00', 'Z'))
PY
}

short_body() {
  python3 - "$1" <<'PY'
import json, sys
p = sys.argv[1]
try:
    data = open(p, 'r', encoding='utf-8').read()
    try:
        obj = json.loads(data)
        sensitive = {'access_token','refresh_token','authorization','password','new_password','current_password','token','jwt','secret'}
        def redact(x):
            if isinstance(x, dict):
                return {k: ('<redacted>' if k.lower() in sensitive or 'token' in k.lower() or 'secret' in k.lower() or 'password' in k.lower() else redact(v)) for k, v in x.items()}
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
  TEST_COUNT=$((TEST_COUNT + 1)); PASS_COUNT=$((PASS_COUNT + 1))
  printf "%s[PASS]%s %s\n" "$GREEN" "$RESET" "$1"
}
record_fail() {
  TEST_COUNT=$((TEST_COUNT + 1)); FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "%s[FAIL]%s %s\n" "$RED" "$RESET" "$1"
  if [ "${2:-}" != "" ]; then echo "       $2"; fi
}
record_skip() {
  TEST_COUNT=$((TEST_COUNT + 1)); SKIP_COUNT=$((SKIP_COUNT + 1))
  printf "%s[SKIP]%s %s\n" "$YELLOW" "$RESET" "$1"
  if [ "${2:-}" != "" ]; then echo "       $2"; fi
}

validate_json_envelope() {
  local name="$1" file="$2" code="$3" path="$4"
  python3 - "$file" "$code" "$path" <<'PY'
import json, sys
file_path, code, path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
try:
    obj = json.load(open(file_path, 'r', encoding='utf-8'))
except Exception as e:
    print(f'not valid JSON: {e}')
    sys.exit(1)
if path in ('/hello','/health') and code < 400:
    if obj.get('status') in ('ok','down'):
        sys.exit(0)
    print('system endpoint success/health response missing status ok/down')
    sys.exit(1)
if code >= 400:
    required = ['status','message','error_code','details','path','request_id','trace_id','timestamp']
    missing = [k for k in required if k not in obj]
    if missing or obj.get('status') != 'error':
        print(f'bad error envelope missing={missing} status={obj.get("status")}')
        sys.exit(1)
else:
    required = ['status','message','data','request_id','trace_id','timestamp']
    missing = [k for k in required if k not in obj]
    if missing or obj.get('status') != 'ok':
        print(f'bad success envelope missing={missing} status={obj.get("status")}')
        sys.exit(1)
PY
}

request_base() {
  local base_url="$1" name="$2" method="$3" path="$4" expected="$5" body="${6:-}" token="${7:-}" envelope="${8:-json}"
  local safe outfile req_id trace_id http_code curl_exit
  safe="$(safe_name "$name")"
  outfile="$TMP_DIR/${safe}.json"
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
  if [ "$token" != "" ]; then curl_args+=( -H "Authorization: Bearer $token" ); fi
  if [ "$body" != "" ]; then curl_args+=( -H "Content-Type: application/json" -d "$body" ); fi
  http_code="$(curl "${curl_args[@]}" 2>"$outfile.curlerr")"
  curl_exit=$?
  echo "$outfile" > "$TMP_DIR/${safe}.path"
  echo "$http_code" > "$TMP_DIR/${safe}.code"
  if [ "$VERBOSE" = "1" ]; then
    echo "--- $name response ($http_code) ---"
    short_body "$outfile"
    echo "-------------------------------"
  fi
  if [ "$curl_exit" -ne 0 ]; then
    record_fail "$name" "curl failed: $(cat "$outfile.curlerr")"
    return 1
  fi
  if ! printf '%s' "$http_code" | grep -Eq "^(${expected})$"; then
    record_fail "$name" "expected HTTP $expected, got $http_code; body: $(short_body "$outfile")"
    return 1
  fi
  if [ "$envelope" = "json" ]; then
    if ! err="$(validate_json_envelope "$name" "$outfile" "$http_code" "$path" 2>&1)"; then
      record_fail "$name envelope" "$err; body: $(short_body "$outfile")"
      return 1
    fi
  fi
  record_pass "$name ($http_code)"
  return 0
}

user_request() { request_base "$USER_SERVICE_URL" "$@"; }
auth_request() { request_base "$AUTH_SERVICE_URL" "$@"; }

last_file() { cat "$TMP_DIR/$(safe_name "$1").path" 2>/dev/null || true; }

signup_user() {
  local username="$1" email="$2" password="$3" full_name="$4"
  local body
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
  auth_request "auth signup $username" "POST" "/v1/signup" "200|201|409" "$body" "" "json"
}

signin_user() {
  local username="$1" password="$2" device="$3" name="$4"
  local body
  body=$(cat <<JSON
{
  "username_or_email": "$username",
  "password": "$password",
  "device_id": "$device"
}
JSON
)
  auth_request "$name" "POST" "$AUTH_LOGIN_PATH" "200" "$body" "" "json"
}

get_or_create_tokens() {
  if [ "$ACCESS_TOKEN" = "" ]; then
    if [ "$CREATE_USER" = "1" ]; then
      signup_user "$TEST_USERNAME" "$TEST_EMAIL" "$TEST_PASSWORD" "User Service Smoke Test User"
    fi
    signin_user "$TEST_USERNAME" "$TEST_PASSWORD" "user-service-smoke-$RUN_ID" "auth primary user signin"
    local file
    file="$(last_file "auth primary user signin")"
    ACCESS_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  fi
  USER_ID="$(jwt_sub "$ACCESS_TOKEN")"
  if [ "$USER_ID" = "" ]; then
    record_fail "primary user id extracted" "Could not parse sub from access token."
  else
    record_pass "primary user id extracted: $USER_ID"
  fi

  if [ "$SECOND_TOKEN" = "" ] && [ "$AUTH_SERVICE_URL" != "" ]; then
    signup_user "$SECOND_USERNAME" "$SECOND_EMAIL" "$SECOND_PASSWORD" "User Service Smoke Test Second User"
    signin_user "$SECOND_USERNAME" "$SECOND_PASSWORD" "user-service-smoke-second-$RUN_ID" "auth second user signin"
    local file2
    file2="$(last_file "auth second user signin")"
    SECOND_TOKEN="$(json_get_any "$file2" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  fi
  if [ "$SECOND_TOKEN" != "" ]; then
    SECOND_USER_ID="$(jwt_sub "$SECOND_TOKEN")"
    if [ "$SECOND_USER_ID" = "" ]; then
      record_skip "second user id extracted" "Could not parse sub from second token."
    else
      record_pass "second user id extracted: $SECOND_USER_ID"
    fi
  fi
}

print_section() { printf "\n%s%s%s\n" "$BOLD" "$1" "$RESET"; }

print_section "Public system API"
user_request "hello" "GET" "/hello" "200" "" "" "json"
user_request "health" "GET" "/health" "200|503" "" "" "json"
user_request "docs" "GET" "/docs" "200" "" "" "html"
user_request "rejected root" "GET" "/" "404" "" "" "json"
user_request "rejected live" "GET" "/live" "404" "" "" "json"
user_request "rejected ready" "GET" "/ready" "404" "" "" "json"
user_request "rejected healthy" "GET" "/healthy" "404" "" "" "json"
user_request "hello wrong method" "POST" "/hello" "405" "{}" "" "json"

print_section "Authentication contract"
user_request "me missing token" "GET" "/v1/users/me" "401" "" "" "json"
user_request "me invalid token" "GET" "/v1/users/me" "401" "" "not-a-real-token" "json"

get_or_create_tokens
if [ "$ACCESS_TOKEN" = "" ] || [ "$USER_ID" = "" ]; then
  echo "Cannot continue protected user-service tests without primary access token and user id."
  exit 1
fi

print_section "Profile, preferences, security, dashboard"
user_request "current profile" "GET" "/v1/users/me" "200" "" "$ACCESS_TOKEN" "json"
PROFILE_PATCH=$(cat <<JSON
{"full_name":"User Service Smoke Test User","display_name":"UserSmoke","bio":"Testing user_service APIs","timezone":"Asia/Dhaka","locale":"en","metadata":{"run_id":"$RUN_ID"}}
JSON
)
user_request "update profile" "PATCH" "/v1/users/me" "200" "$PROFILE_PATCH" "$ACCESS_TOKEN" "json"
user_request "update profile malformed json" "PATCH" "/v1/users/me" "400" "{" "$ACCESS_TOKEN" "json"
user_request "preferences" "GET" "/v1/users/me/preferences" "200" "" "$ACCESS_TOKEN" "json"
PREF_BODY=$(cat <<JSON
{"timezone":"Asia/Dhaka","locale":"en","theme":"dark","notifications_enabled":true,"dashboard_settings":{"density":"comfortable"},"report_settings":{"default_format":"pdf"},"metadata":{"run_id":"$RUN_ID"}}
JSON
)
user_request "replace preferences" "PUT" "/v1/users/me/preferences" "200" "$PREF_BODY" "$ACCESS_TOKEN" "json"
user_request "replace preferences malformed json" "PUT" "/v1/users/me/preferences" "400" "{" "$ACCESS_TOKEN" "json"
user_request "dashboard" "GET" "/v1/users/me/dashboard" "200" "" "$ACCESS_TOKEN" "json"
user_request "security context" "GET" "/v1/users/me/security-context" "200" "" "$ACCESS_TOKEN" "json"
user_request "rbac view" "GET" "/v1/users/me/rbac" "200" "" "$ACCESS_TOKEN" "json"
user_request "effective permissions" "GET" "/v1/users/me/effective-permissions" "200" "" "$ACCESS_TOKEN" "json"

print_section "Invalid query-string coverage"
user_request "activity invalid limit text" "GET" "/v1/users/me/activity?limit=abc" "400" "" "$ACCESS_TOKEN" "json"
user_request "activity invalid limit zero" "GET" "/v1/users/me/activity?limit=0" "400" "" "$ACCESS_TOKEN" "json"
user_request "activity invalid limit too large" "GET" "/v1/users/me/activity?limit=101" "400" "" "$ACCESS_TOKEN" "json"
user_request "activity invalid offset text" "GET" "/v1/users/me/activity?offset=abc" "400" "" "$ACCESS_TOKEN" "json"
user_request "activity invalid offset negative" "GET" "/v1/users/me/activity?offset=-1" "400" "" "$ACCESS_TOKEN" "json"
user_request "activity valid paging" "GET" "/v1/users/me/activity?limit=10&offset=0" "200" "" "$ACCESS_TOKEN" "json"

print_section "Projection reads"
user_request "own calculations list" "GET" "/v1/users/me/calculations?limit=20&offset=0" "200" "" "$ACCESS_TOKEN" "json"
user_request "own missing calculation detail" "GET" "/v1/users/me/calculations/missing-calculation-id" "404" "" "$ACCESS_TOKEN" "json"
user_request "own todos list" "GET" "/v1/users/me/todos?limit=20&offset=0" "200" "" "$ACCESS_TOKEN" "json"
user_request "own todos summary" "GET" "/v1/users/me/todos/summary" "200" "" "$ACCESS_TOKEN" "json"
user_request "own todos activity" "GET" "/v1/users/me/todos/activity?limit=20&offset=0" "200" "" "$ACCESS_TOKEN" "json"
user_request "own missing todo detail" "GET" "/v1/users/me/todos/missing-todo-id" "404" "" "$ACCESS_TOKEN" "json"
user_request "report types" "GET" "/v1/users/reports/types" "200" "" "$ACCESS_TOKEN" "json"

if [ "$SECOND_TOKEN" != "" ] && [ "$SECOND_USER_ID" != "" ]; then
  print_section "Cross-user forbidden checks without grant"
  user_request "second user forbidden primary calculations" "GET" "/v1/users/$USER_ID/calculations?limit=10" "403" "" "$SECOND_TOKEN" "json"
  user_request "second user forbidden primary todos" "GET" "/v1/users/$USER_ID/todos?limit=10" "403" "" "$SECOND_TOKEN" "json"
  user_request "second user forbidden primary reports" "GET" "/v1/users/$USER_ID/reports?limit=10" "403" "" "$SECOND_TOKEN" "json"
fi

print_section "Access request flow and validation"
user_request "access request missing body" "POST" "/v1/users/access-requests" "400" "{}" "$ACCESS_TOKEN" "json"
TOO_LONG_EXPIRES="2035-01-01T00:00:00Z"
ACCESS_TOO_LONG=$(cat <<JSON
{"target_user_id":"target-$RUN_ID","resource_type":"calculator","scope":"calculator:history:read","reason":"ttl validation","expires_at":"$TOO_LONG_EXPIRES"}
JSON
)
user_request "access request ttl exceeded" "POST" "/v1/users/access-requests" "400" "$ACCESS_TOO_LONG" "$ACCESS_TOKEN" "json"
ACCESS_EXPIRES="$(future_rfc3339 14)"
ACCESS_BODY=$(cat <<JSON
{"target_user_id":"target-$RUN_ID","resource_type":"calculator","scope":"calculator:history:read","reason":"Need to test access request lifecycle.","expires_at":"$ACCESS_EXPIRES"}
JSON
)
user_request "create access request" "POST" "/v1/users/access-requests" "201" "$ACCESS_BODY" "$ACCESS_TOKEN" "json"
ACCESS_FILE="$(last_file "create access request")"
ACCESS_REQUEST_ID="$(json_get_any "$ACCESS_FILE" "data.request_id" "data.id" "request_id")"
if [ "$ACCESS_REQUEST_ID" = "" ]; then
  record_fail "access request id extracted" "No request id in create response."
else
  record_pass "access request id extracted: $ACCESS_REQUEST_ID"
  user_request "list access requests" "GET" "/v1/users/access-requests?limit=20&offset=0" "200" "" "$ACCESS_TOKEN" "json"
  user_request "get access request" "GET" "/v1/users/access-requests/$ACCESS_REQUEST_ID" "200" "" "$ACCESS_TOKEN" "json"
  user_request "cancel access request" "POST" "/v1/users/access-requests/$ACCESS_REQUEST_ID/cancel" "200" "" "$ACCESS_TOKEN" "json"
  user_request "cancel access request conflict" "POST" "/v1/users/access-requests/$ACCESS_REQUEST_ID/cancel" "409" "" "$ACCESS_TOKEN" "json"
fi
user_request "unknown access request" "GET" "/v1/users/access-requests/missing-request-id" "404" "" "$ACCESS_TOKEN" "json"
user_request "list access grants" "GET" "/v1/users/access-grants?limit=20&offset=0" "200" "" "$ACCESS_TOKEN" "json"

print_section "Report request flow and validation"
user_request "report missing body" "POST" "/v1/users/me/reports" "400" "{}" "$ACCESS_TOKEN" "json"
REPORT_BAD_FORMAT=$(cat <<JSON
{"report_type":"calculator_history_report","format":"docx","date_from":"2026-05-01","date_to":"2026-05-09","filters":{},"options":{}}
JSON
)
user_request "report unsupported format" "POST" "/v1/users/me/reports" "400" "$REPORT_BAD_FORMAT" "$ACCESS_TOKEN" "json"
REPORT_BODY=$(cat <<JSON
{"report_type":"calculator_history_report","format":"pdf","date_from":"2026-05-01","date_to":"2026-05-09","filters":{"source":"smoke"},"options":{"run_id":"$RUN_ID"}}
JSON
)
user_request "create own report" "POST" "/v1/users/me/reports" "201" "$REPORT_BODY" "$ACCESS_TOKEN" "json"
REPORT_FILE="$(last_file "create own report")"
REPORT_ID="$(json_get_any "$REPORT_FILE" "data.report_id" "data.id" "report_id")"
if [ "$REPORT_ID" = "" ]; then
  record_fail "report id extracted" "No report_id in create response."
else
  record_pass "report id extracted: $REPORT_ID"
  user_request "list own reports" "GET" "/v1/users/me/reports?limit=20&offset=0" "200" "" "$ACCESS_TOKEN" "json"
  user_request "get own report" "GET" "/v1/users/me/reports/$REPORT_ID" "200" "" "$ACCESS_TOKEN" "json"
  user_request "own report metadata" "GET" "/v1/users/me/reports/$REPORT_ID/metadata" "200" "" "$ACCESS_TOKEN" "json"
  user_request "own report progress" "GET" "/v1/users/me/reports/$REPORT_ID/progress" "200" "" "$ACCESS_TOKEN" "json"
  user_request "cancel own report" "POST" "/v1/users/me/reports/$REPORT_ID/cancel" "200" "" "$ACCESS_TOKEN" "json"
  user_request "cancel own report conflict" "POST" "/v1/users/me/reports/$REPORT_ID/cancel" "409" "" "$ACCESS_TOKEN" "json"
fi
user_request "unknown report" "GET" "/v1/users/me/reports/missing-report-id" "404" "" "$ACCESS_TOKEN" "json"
user_request "wrong method protected" "DELETE" "/v1/users/me" "405" "" "$ACCESS_TOKEN" "json"
user_request "unknown protected path" "GET" "/v1/users/not-a-real-path" "404" "" "$ACCESS_TOKEN" "json"

printf "\n%sSummary%s\n" "$BOLD" "$RESET"
echo "User service URL:  $USER_SERVICE_URL"
echo "Auth service URL:  $AUTH_SERVICE_URL"
echo "Primary user id:   $USER_ID"
echo "Second user id:    $SECOND_USER_ID"
echo "Access request id: $ACCESS_REQUEST_ID"
echo "Report id:         $REPORT_ID"
echo "Tests:             $TEST_COUNT"
echo "Passed:            $PASS_COUNT"
echo "Failed:            $FAIL_COUNT"
echo "Skipped:           $SKIP_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
exit 0
