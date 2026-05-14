#!/usr/bin/env bash
# Auth Service smoke test script
# Usage:
#   chmod +x auth_service_smoke_test.sh
#   ./auth_service_smoke_test.sh 192.168.56.100
#   ./auth_service_smoke_test.sh 192.168.56.100 6060
#   ./auth_service_smoke_test.sh http://52.66.223.53:6060
#
# Optional environment variables:
#   AUTH_TEST_ADMIN_USERNAME=admin
#   AUTH_TEST_ADMIN_PASSWORD=admin123
#   AUTH_TEST_TIMEOUT=20
#   AUTH_TEST_VERBOSE=1

set -u

if [ "${1:-}" = "" ]; then
  echo "Usage: $0 <ip-or-base-url> [port]"
  echo "Examples:"
  echo "  $0 192.168.56.100"
  echo "  $0 192.168.56.100 6060"
  echo "  $0 http://52.66.223.53:6060"
  exit 2
fi

INPUT="$1"
PORT="${2:-6060}"
TIMEOUT="${AUTH_TEST_TIMEOUT:-20}"
VERBOSE="${AUTH_TEST_VERBOSE:-0}"

if printf '%s' "$INPUT" | grep -Eq '^https?://'; then
  BASE_URL="${INPUT%/}"
else
  BASE_URL="http://${INPUT}:${PORT}"
fi

ADMIN_USERNAME="${AUTH_TEST_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${AUTH_TEST_ADMIN_PASSWORD:-admin123}"
RUN_ID="$(date +%s)-$RANDOM"
NORMAL_USERNAME="authuser_${RUN_ID}"
NORMAL_EMAIL="${NORMAL_USERNAME}@example.com"
INITIAL_PASSWORD="${AUTH_TEST_INITIAL_PASSWORD:-Test1234!Aa}"
RESET_PASSWORD="${AUTH_TEST_RESET_PASSWORD:-Reset1234!Aa}"
CHANGED_PASSWORD="${AUTH_TEST_CHANGED_PASSWORD:-Changed1234!Aa}"
PENDING_ADMIN_USERNAME="authadmin_${RUN_ID}"
PENDING_ADMIN_EMAIL="${PENDING_ADMIN_USERNAME}@example.com"
PENDING_ADMIN_PASSWORD="${AUTH_TEST_PENDING_ADMIN_PASSWORD:-Admin1234!Aa}"

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

json_get() {
  # json_get <file> <dot.path>
  python3 - "$1" "$2" <<'PY'
import json, sys
file_path, key_path = sys.argv[1], sys.argv[2]
try:
    with open(file_path, 'r', encoding='utf-8') as f:
        obj = json.load(f)
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
        # Redact tokens if any accidentally appear in failure output.
        def redact(x):
            if isinstance(x, dict):
                out = {}
                for k, v in x.items():
                    if k.lower() in {'access_token','refresh_token','authorization','password','new_password','current_password'}:
                        out[k] = '<redacted>'
                    else:
                        out[k] = redact(v)
                return out
            if isinstance(x, list):
                return [redact(i) for i in x]
            return x
        print(json.dumps(redact(obj), indent=2)[:1600])
    except Exception:
        print(data[:1600])
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

request() {
  # request <name> <method> <path> <expected_codes_regex> <body_or_empty> <bearer_token_or_empty>
  local name="$1"
  local method="$2"
  local path="$3"
  local expected="$4"
  local body="${5:-}"
  local token="${6:-}"
  local outfile="$TMP_DIR/${name//[^A-Za-z0-9_]/_}.json"
  local req_id="req-$(new_uuid)"
  local trace_id="$(new_uuid | tr -d '-')"
  local http_code curl_exit

  local curl_args=(
    -sS
    --connect-timeout 5
    --max-time "$TIMEOUT"
    -o "$outfile"
    -w "%{http_code}"
    -X "$method"
    "$BASE_URL$path"
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

  record_fail "$name ($method $path expected HTTP $expected but got $http_code)" "response: $(short_body "$outfile" | tr '\n' ' ' | cut -c1-900)"
  return 1
}

last_file() {
  cat "$TMP_DIR/${1//[^A-Za-z0-9_]/_}.path" 2>/dev/null || true
}

print_header() {
  echo "${BOLD}${BLUE}Auth Service Smoke Test${RESET}"
  echo "Base URL: $BASE_URL"
  echo "Timeout:  ${TIMEOUT}s"
  echo "Run ID:   $RUN_ID"
  echo
}

print_header

# Public system routes
request "hello" "GET" "/hello" "200" "" ""
HELLO_FILE="$(last_file hello)"
if [ -n "$HELLO_FILE" ] && [ "$(json_status "$HELLO_FILE")" != "ok" ]; then
  record_fail "hello envelope status" "expected JSON status=ok"
else
  record_pass "hello envelope status is ok"
fi

request "health" "GET" "/health" "200" "" ""
HEALTH_FILE="$(last_file health)"
if [ -n "$HEALTH_FILE" ] && [ "$(json_status "$HEALTH_FILE")" != "ok" ]; then
  record_fail "health envelope status" "expected JSON status=ok. Dependency may be down: $(short_body "$HEALTH_FILE" | tr '\n' ' ' | cut -c1-700)"
else
  record_pass "health envelope status is ok"
fi

request "docs" "GET" "/docs" "200" "" ""
request "root rejected" "GET" "/" "404" "" ""
request "live rejected" "GET" "/live" "404" "" ""
request "ready rejected" "GET" "/ready" "404" "" ""
request "healthy rejected" "GET" "/healthy" "404" "" ""
request "openapi json rejected" "GET" "/openapi.json" "404" "" ""

# Protected routes without token
request "me without token" "GET" "/v1/me" "401" "" ""
request "admin requests without token" "GET" "/v1/admin/requests" "401" "" ""

# Signup normal user
SIGNUP_BODY=$(cat <<JSON
{
  "username": "$NORMAL_USERNAME",
  "email": "$NORMAL_EMAIL",
  "password": "$INITIAL_PASSWORD",
  "full_name": "Smoke Test User",
  "birthdate": "1998-05-20",
  "gender": "male",
  "account_type": "user"
}
JSON
)
request "signup user" "POST" "/v1/signup" "200" "$SIGNUP_BODY" ""
SIGNUP_FILE="$(last_file "signup user")"
SIGNUP_ACCESS_TOKEN="$(json_get "$SIGNUP_FILE" "data.tokens.access_token")"
SIGNUP_REFRESH_TOKEN="$(json_get "$SIGNUP_FILE" "data.tokens.refresh_token")"
USER_ID="$(json_get "$SIGNUP_FILE" "data.user.id")"
if [ "$SIGNUP_ACCESS_TOKEN" = "" ] || [ "$SIGNUP_REFRESH_TOKEN" = "" ] || [ "$USER_ID" = "" ]; then
  record_fail "signup returned tokens and user id" "missing access_token, refresh_token, or user id"
else
  record_pass "signup returned tokens and user id"
fi

# Signin preferred endpoint
SIGNIN_BODY=$(cat <<JSON
{
  "username_or_email": "$NORMAL_USERNAME",
  "password": "$INITIAL_PASSWORD",
  "device_id": "bash-smoke-test"
}
JSON
)
request "signin" "POST" "/v1/signin" "200" "$SIGNIN_BODY" ""
SIGNIN_FILE="$(last_file signin)"
ACCESS_TOKEN="$(json_get "$SIGNIN_FILE" "data.tokens.access_token")"
REFRESH_TOKEN="$(json_get "$SIGNIN_FILE" "data.tokens.refresh_token")"
if [ "$ACCESS_TOKEN" = "" ] || [ "$REFRESH_TOKEN" = "" ]; then
  record_fail "signin returned token pair" "missing access_token or refresh_token"
else
  record_pass "signin returned token pair"
fi

# Login alias
request "login alias" "POST" "/v1/login" "200" "$SIGNIN_BODY" ""
LOGIN_FILE="$(last_file "login alias")"
LOGIN_ACCESS_TOKEN="$(json_get "$LOGIN_FILE" "data.tokens.access_token")"
LOGIN_REFRESH_TOKEN="$(json_get "$LOGIN_FILE" "data.tokens.refresh_token")"
if [ "$LOGIN_ACCESS_TOKEN" != "" ]; then
  ACCESS_TOKEN="$LOGIN_ACCESS_TOKEN"
fi
if [ "$LOGIN_REFRESH_TOKEN" != "" ]; then
  REFRESH_TOKEN="$LOGIN_REFRESH_TOKEN"
fi

# Authenticated current-user and verify
if [ "$ACCESS_TOKEN" != "" ]; then
  request "me with token" "GET" "/v1/me" "200" "" "$ACCESS_TOKEN"
  request "verify token" "GET" "/v1/verify" "200" "" "$ACCESS_TOKEN"
else
  record_skip "me with token" "no access token available"
  record_skip "verify token" "no access token available"
fi

# Refresh token
if [ "$REFRESH_TOKEN" != "" ]; then
  REFRESH_BODY=$(cat <<JSON
{
  "refresh_token": "$REFRESH_TOKEN"
}
JSON
)
  request "refresh token" "POST" "/v1/token/refresh" "200" "$REFRESH_BODY" ""
  REFRESH_FILE="$(last_file "refresh token")"
  NEW_ACCESS_TOKEN="$(json_get "$REFRESH_FILE" "data.tokens.access_token")"
  NEW_REFRESH_TOKEN="$(json_get "$REFRESH_FILE" "data.tokens.refresh_token")"
  if [ "$NEW_ACCESS_TOKEN" != "" ]; then ACCESS_TOKEN="$NEW_ACCESS_TOKEN"; fi
  if [ "$NEW_REFRESH_TOKEN" != "" ]; then REFRESH_TOKEN="$NEW_REFRESH_TOKEN"; fi
else
  record_skip "refresh token" "no refresh token available"
fi

# Password forgot/reset flow
FORGOT_BODY=$(cat <<JSON
{
  "email": "$NORMAL_EMAIL"
}
JSON
)
request "password forgot" "POST" "/v1/password/forgot" "200" "$FORGOT_BODY" ""
FORGOT_FILE="$(last_file "password forgot")"
RESET_TOKEN="$(json_get "$FORGOT_FILE" "data.reset_token")"
CURRENT_PASSWORD="$INITIAL_PASSWORD"

if [ "$RESET_TOKEN" != "" ]; then
  RESET_BODY=$(cat <<JSON
{
  "reset_token": "$RESET_TOKEN",
  "new_password": "$RESET_PASSWORD"
}
JSON
)
  request "password reset" "POST" "/v1/password/reset" "200" "$RESET_BODY" ""
  CURRENT_PASSWORD="$RESET_PASSWORD"

  SIGNIN_AFTER_RESET_BODY=$(cat <<JSON
{
  "username_or_email": "$NORMAL_USERNAME",
  "password": "$CURRENT_PASSWORD",
  "device_id": "bash-smoke-test-after-reset"
}
JSON
)
  request "signin after password reset" "POST" "/v1/signin" "200" "$SIGNIN_AFTER_RESET_BODY" ""
  SIGNIN_RESET_FILE="$(last_file "signin after password reset")"
  ACCESS_TOKEN="$(json_get "$SIGNIN_RESET_FILE" "data.tokens.access_token")"
else
  record_skip "password reset" "no reset_token returned. In production this can be expected; in development it should usually be returned."
fi

# Password change
if [ "$ACCESS_TOKEN" != "" ]; then
  CHANGE_BODY=$(cat <<JSON
{
  "current_password": "$CURRENT_PASSWORD",
  "new_password": "$CHANGED_PASSWORD"
}
JSON
)
  request "password change" "POST" "/v1/password/change" "200" "$CHANGE_BODY" "$ACCESS_TOKEN"
  CURRENT_PASSWORD="$CHANGED_PASSWORD"

  SIGNIN_CHANGED_BODY=$(cat <<JSON
{
  "username_or_email": "$NORMAL_USERNAME",
  "password": "$CURRENT_PASSWORD",
  "device_id": "bash-smoke-test-after-change"
}
JSON
)
  request "signin after password change" "POST" "/v1/signin" "200" "$SIGNIN_CHANGED_BODY" ""
  SIGNIN_CHANGED_FILE="$(last_file "signin after password change")"
  ACCESS_TOKEN="$(json_get "$SIGNIN_CHANGED_FILE" "data.tokens.access_token")"
else
  record_skip "password change" "no access token available"
fi

# Logout and token revocation check
if [ "$ACCESS_TOKEN" != "" ]; then
  request "logout" "POST" "/v1/logout" "200" "" "$ACCESS_TOKEN"
  request "me with revoked token" "GET" "/v1/me" "401" "" "$ACCESS_TOKEN"
else
  record_skip "logout" "no access token available"
  record_skip "me with revoked token" "no access token available"
fi

# Admin registration request
ADMIN_REGISTER_BODY=$(cat <<JSON
{
  "username": "$PENDING_ADMIN_USERNAME",
  "email": "$PENDING_ADMIN_EMAIL",
  "password": "$PENDING_ADMIN_PASSWORD",
  "full_name": "Smoke Test Pending Admin",
  "birthdate": "1998-05-20",
  "gender": "male",
  "account_type": "admin",
  "reason": "I need admin access to verify the auth service admin approval flow."
}
JSON
)
request "admin register request" "POST" "/v1/admin/register" "200" "$ADMIN_REGISTER_BODY" ""
ADMIN_REGISTER_FILE="$(last_file "admin register request")"
PENDING_ADMIN_ID="$(json_get "$ADMIN_REGISTER_FILE" "data.user.id")"
if [ "$PENDING_ADMIN_ID" = "" ]; then
  record_fail "admin register returned pending admin id" "missing data.user.id"
else
  record_pass "admin register returned pending admin id"
fi

# Approved admin-only endpoints using default bootstrap admin credentials.
BOOTSTRAP_ADMIN_BODY=$(cat <<JSON
{
  "username_or_email": "$ADMIN_USERNAME",
  "password": "$ADMIN_PASSWORD",
  "device_id": "bash-smoke-test-admin"
}
JSON
)
request "bootstrap admin signin" "POST" "/v1/signin" "200" "$BOOTSTRAP_ADMIN_BODY" ""
BOOTSTRAP_ADMIN_FILE="$(last_file "bootstrap admin signin")"
ADMIN_TOKEN="$(json_get "$BOOTSTRAP_ADMIN_FILE" "data.tokens.access_token")"
ADMIN_ROLE="$(json_get "$BOOTSTRAP_ADMIN_FILE" "data.user.role")"
ADMIN_STATUS="$(json_get "$BOOTSTRAP_ADMIN_FILE" "data.user.admin_status")"

if [ "$ADMIN_TOKEN" = "" ]; then
  record_skip "list admin requests" "default admin signin failed. Set AUTH_TEST_ADMIN_USERNAME and AUTH_TEST_ADMIN_PASSWORD if different."
  record_skip "admin request decision" "default admin signin failed."
else
  if [ "$ADMIN_ROLE" != "admin" ] || [ "$ADMIN_STATUS" != "approved" ]; then
    record_fail "bootstrap admin is approved admin" "role=$ADMIN_ROLE admin_status=$ADMIN_STATUS"
  else
    record_pass "bootstrap admin is approved admin"
  fi

  request "list admin requests" "GET" "/v1/admin/requests" "200" "" "$ADMIN_TOKEN"

  if [ "$PENDING_ADMIN_ID" != "" ]; then
    DECISION_BODY=$(cat <<JSON
{
  "decision": "approve",
  "reason": "Approved by auth service smoke test."
}
JSON
)
    request "admin request decision" "POST" "/v1/admin/requests/$PENDING_ADMIN_ID/decision" "200" "$DECISION_BODY" "$ADMIN_TOKEN"

    PENDING_ADMIN_SIGNIN_BODY=$(cat <<JSON
{
  "username_or_email": "$PENDING_ADMIN_USERNAME",
  "password": "$PENDING_ADMIN_PASSWORD",
  "device_id": "bash-smoke-test-approved-admin"
}
JSON
)
    request "approved admin can signin" "POST" "/v1/signin" "200" "$PENDING_ADMIN_SIGNIN_BODY" ""
    APPROVED_ADMIN_FILE="$(last_file "approved admin can signin")"
    APPROVED_ADMIN_STATUS="$(json_get "$APPROVED_ADMIN_FILE" "data.user.admin_status")"
    if [ "$APPROVED_ADMIN_STATUS" = "approved" ]; then
      record_pass "approved admin signin shows admin_status=approved"
    else
      record_fail "approved admin signin shows admin_status=approved" "actual admin_status=$APPROVED_ADMIN_STATUS"
    fi
  else
    record_skip "admin request decision" "pending admin id missing"
  fi
fi

echo
printf "%sSummary:%s %s total, %s passed, %s failed, %s skipped\n" "$BOLD" "$RESET" "$TEST_COUNT" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
echo "Test user:          $NORMAL_USERNAME / $NORMAL_EMAIL"
echo "Pending admin user: $PENDING_ADMIN_USERNAME / $PENDING_ADMIN_EMAIL"
echo "Base URL:           $BASE_URL"

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo
  echo "One or more auth service checks failed. Review the failure messages above."
  exit 1
fi

echo
printf "%sAll required auth service checks passed.%s\n" "$GREEN" "$RESET"
exit 0



# Make the script executable and run it
# chmod +x auth_service_smoke_test.sh

# By default it will target port 6060, but you can specify a different port or full base URL as an argument:
# ./auth_service_smoke_test.sh 192.168.56.100 6060
# AUTH_TEST_VERBOSE=1 ./auth_service_smoke_test.sh 192.168.56.100 6060

# If your admin credentials are different from the defaults, set them as environment variables before running the test:
# AUTH_TEST_ADMIN_USERNAME=admin AUTH_TEST_ADMIN_PASSWORD='admin123' ./auth_service_smoke_test.sh 192.168.56.100 6060
# AUTH_TEST_VERBOSE=1 AUTH_TEST_ADMIN_USERNAME=admin AUTH_TEST_ADMIN_PASSWORD='admin123' ./auth_service_smoke_test.sh 192.168.56.100 6060
