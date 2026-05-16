#!/usr/bin/env bash
# Auth Service full API and integration test script
#
# Usage:
#   chmod +x auth_service_full_api_test.sh
#   cp auth_service_full_api_test.env.example auth_service_full_api_test.env
#   ./auth_service_full_api_test.sh ./auth_service_full_api_test.env
#
# The script tests Auth service public routes, rejected routes, all canonical /v1 auth APIs,
# valid and invalid request bodies, JWT/session behavior, admin registration approval flow,
# and optional downstream service JWT/projection checks.

set -u

ENV_FILE="${1:-./auth_service_full_api_test.env}"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi

AUTH_BASE_URL="${AUTH_BASE_URL:-http://3.108.225.164:6060}"
ADMIN_BASE_URL="${ADMIN_BASE_URL:-http://3.108.225.164:1010}"
USER_BASE_URL="${USER_BASE_URL:-http://3.108.225.164:4040}"
CALCULATOR_BASE_URL="${CALCULATOR_BASE_URL:-http://3.108.225.164:2020}"
TODO_BASE_URL="${TODO_BASE_URL:-http://3.108.225.164:3030}"
REPORT_BASE_URL="${REPORT_BASE_URL:-http://3.108.225.164:5050}"

AUTH_TEST_TIMEOUT="${AUTH_TEST_TIMEOUT:-25}"
AUTH_TEST_VERBOSE="${AUTH_TEST_VERBOSE:-0}"
AUTH_TEST_SAVE_RESPONSES="${AUTH_TEST_SAVE_RESPONSES:-0}"
AUTH_TEST_RESPONSE_DIR="${AUTH_TEST_RESPONSE_DIR:-}"
AUTH_TEST_DOWNSTREAM_ENABLED="${AUTH_TEST_DOWNSTREAM_ENABLED:-1}"
AUTH_TEST_DOWNSTREAM_MUTATE="${AUTH_TEST_DOWNSTREAM_MUTATE:-0}"
AUTH_TEST_PROJECTION_RETRIES="${AUTH_TEST_PROJECTION_RETRIES:-12}"
AUTH_TEST_PROJECTION_SLEEP_SECONDS="${AUTH_TEST_PROJECTION_SLEEP_SECONDS:-2}"
AUTH_TEST_REQUIRE_HEALTH_OK="${AUTH_TEST_REQUIRE_HEALTH_OK:-1}"
AUTH_TEST_EXPECT_OPENAPI_PUBLIC="${AUTH_TEST_EXPECT_OPENAPI_PUBLIC:-0}"
AUTH_TEST_ADMIN_FORWARDED_PROTO="${AUTH_TEST_ADMIN_FORWARDED_PROTO:-}"
AUTH_TEST_AUTH_FORWARDED_PROTO="${AUTH_TEST_AUTH_FORWARDED_PROTO:-}"
AUTH_TEST_USER_FORWARDED_PROTO="${AUTH_TEST_USER_FORWARDED_PROTO:-}"
AUTH_TEST_CALCULATOR_FORWARDED_PROTO="${AUTH_TEST_CALCULATOR_FORWARDED_PROTO:-}"
AUTH_TEST_TODO_FORWARDED_PROTO="${AUTH_TEST_TODO_FORWARDED_PROTO:-}"
AUTH_TEST_REPORT_FORWARDED_PROTO="${AUTH_TEST_REPORT_FORWARDED_PROTO:-}"

AUTH_TEST_ADMIN_USERNAME="${AUTH_TEST_ADMIN_USERNAME:-admin}"
AUTH_TEST_ADMIN_PASSWORD="${AUTH_TEST_ADMIN_PASSWORD:-admin123}"
AUTH_TEST_INITIAL_PASSWORD="${AUTH_TEST_INITIAL_PASSWORD:-Test1234!Aa}"
AUTH_TEST_RESET_PASSWORD="${AUTH_TEST_RESET_PASSWORD:-Reset1234!Aa}"
AUTH_TEST_CHANGED_PASSWORD="${AUTH_TEST_CHANGED_PASSWORD:-Changed1234!Aa}"
AUTH_TEST_PENDING_ADMIN_PASSWORD="${AUTH_TEST_PENDING_ADMIN_PASSWORD:-Admin1234!Aa}"
AUTH_TEST_TENANT="${AUTH_TEST_TENANT:-dev}"
AUTH_TEST_EXPECT_RESET_TOKEN="${AUTH_TEST_EXPECT_RESET_TOKEN:-auto}"

RUN_ID="$(date +%s)-$RANDOM"
NORMAL_USERNAME="${AUTH_TEST_NORMAL_USERNAME:-authuser_${RUN_ID}}"
NORMAL_EMAIL="${AUTH_TEST_NORMAL_EMAIL:-${NORMAL_USERNAME}@example.com}"
PENDING_ADMIN_USERNAME="${AUTH_TEST_PENDING_ADMIN_USERNAME:-authadmin_${RUN_ID}}"
PENDING_ADMIN_EMAIL="${AUTH_TEST_PENDING_ADMIN_EMAIL:-${PENDING_ADMIN_USERNAME}@example.com}"
REJECT_ADMIN_USERNAME="${AUTH_TEST_REJECT_ADMIN_USERNAME:-authreject_${RUN_ID}}"
REJECT_ADMIN_EMAIL="${AUTH_TEST_REJECT_ADMIN_EMAIL:-${REJECT_ADMIN_USERNAME}@example.com}"

if [ -n "$AUTH_TEST_RESPONSE_DIR" ]; then
  TMP_DIR="$AUTH_TEST_RESPONSE_DIR"
  mkdir -p "$TMP_DIR"
  CLEAN_TMP=0
else
  TMP_DIR="$(mktemp -d)"
  CLEAN_TMP=1
fi
trap 'if [ "${CLEAN_TMP:-1}" = "1" ]; then rm -rf "$TMP_DIR"; fi' EXIT

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
WARN_COUNT=0
TEST_COUNT=0

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

iso_utc_days_from_now() {
  python3 - "$1" <<'PY'
from datetime import datetime, timezone, timedelta
import sys
print((datetime.now(timezone.utc) + timedelta(days=int(sys.argv[1]))).replace(microsecond=0).isoformat().replace('+00:00', 'Z'))
PY
}

today_date_utc() {
  python3 - <<'PY'
from datetime import datetime, timezone
print(datetime.now(timezone.utc).date().isoformat())
PY
}

jwt_payload_json() {
  python3 - "$1" <<'PY'
import base64, json, sys
try:
    token = sys.argv[1]
    part = token.split('.')[1]
    part += '=' * (-len(part) % 4)
    print(json.dumps(json.loads(base64.urlsafe_b64decode(part.encode())), separators=(',', ':')))
except Exception:
    print('{}')
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
  for path in "$@"; do
    value="$(json_get "$file" "$path")"
    if [ -n "$value" ]; then
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
secret_keys = {
    'access_token','refresh_token','authorization','password','new_password','current_password',
    'reset_token','token','jwt','secret','jwt_secret','api_key','access_key','secret_key'
}
try:
    data = open(p, 'r', encoding='utf-8').read()
    try:
        obj = json.loads(data)
        def redact(x):
            if isinstance(x, dict):
                out = {}
                for k, v in x.items():
                    if k.lower() in secret_keys or any(s in k.lower() for s in ['password','token','secret','authorization']):
                        out[k] = '<redacted>'
                    else:
                        out[k] = redact(v)
                return out
            if isinstance(x, list):
                return [redact(i) for i in x]
            return x
        print(json.dumps(redact(obj), indent=2)[:2000])
    except Exception:
        print(data[:2000])
except Exception as e:
    print(f'<unable to read response: {e}>')
PY
}

safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_'
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

record_warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf "%s[WARN]%s %s\n" "$YELLOW" "$RESET" "$1"
  if [ "${2:-}" != "" ]; then echo "       $2"; fi
}

service_proto_header() {
  case "$1" in
    auth) printf '%s' "$AUTH_TEST_AUTH_FORWARDED_PROTO" ;;
    admin) printf '%s' "$AUTH_TEST_ADMIN_FORWARDED_PROTO" ;;
    user) printf '%s' "$AUTH_TEST_USER_FORWARDED_PROTO" ;;
    calculator) printf '%s' "$AUTH_TEST_CALCULATOR_FORWARDED_PROTO" ;;
    todo) printf '%s' "$AUTH_TEST_TODO_FORWARDED_PROTO" ;;
    report) printf '%s' "$AUTH_TEST_REPORT_FORWARDED_PROTO" ;;
    *) printf '' ;;
  esac
}

request_to() {
  # request_to <service> <base_url> <name> <method> <path> <expected_codes_regex> <body_or_empty> <bearer_token_or_empty>
  local service="$1"
  local base_url="${2%/}"
  local name="$3"
  local method="$4"
  local path="$5"
  local expected="$6"
  local body="${7:-}"
  local token="${8:-}"
  local safe
  safe="$(safe_name "${service}_${name}")"
  local outfile="$TMP_DIR/${safe}.json"
  local req_id="req-$(new_uuid)"
  local trace_id
  trace_id="$(new_uuid | tr -d '-')"
  local http_code curl_exit proto

  local curl_args=(
    -sS
    --connect-timeout 5
    --max-time "$AUTH_TEST_TIMEOUT"
    -o "$outfile"
    -w "%{http_code}"
    -X "$method"
    "$base_url$path"
    -H "accept: application/json"
    -H "X-Request-ID: $req_id"
    -H "X-Trace-ID: $trace_id"
    -H "X-Correlation-ID: $req_id"
  )

  proto="$(service_proto_header "$service")"
  if [ -n "$proto" ]; then
    curl_args+=( -H "X-Forwarded-Proto: $proto" )
  fi

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

  if [ "$AUTH_TEST_VERBOSE" = "1" ]; then
    echo "--- [$service] $name response ($http_code) ---"
    short_body "$outfile"
    echo "--------------------------------------------"
  fi

  if [ "$curl_exit" -ne 0 ]; then
    record_fail "[$service] $name" "curl failed: $(cat "$outfile.curlerr")"
    return 1
  fi

  if printf '%s' "$http_code" | grep -Eq "^($expected)$"; then
    record_pass "[$service] $name ($method $path -> HTTP $http_code)"
    return 0
  fi

  record_fail "[$service] $name ($method $path expected HTTP $expected but got $http_code)" "response: $(short_body "$outfile" | tr '\n' ' ' | cut -c1-1000)"
  return 1
}

request_auth() {
  request_to auth "$AUTH_BASE_URL" "$@"
}

last_file() {
  local service="$1"
  local name="$2"
  local safe
  safe="$(safe_name "${service}_${name}")"
  cat "$TMP_DIR/${safe}.path" 2>/dev/null || true
}

assert_json_status() {
  local service="$1"
  local name="$2"
  local expected="$3"
  local file
  file="$(last_file "$service" "$name")"
  if [ -z "$file" ]; then
    record_fail "[$service] $name JSON status" "response file not found"
    return 1
  fi
  local actual
  actual="$(json_status "$file")"
  if [ "$actual" = "$expected" ]; then
    record_pass "[$service] $name envelope status=$expected"
  else
    record_fail "[$service] $name envelope status" "expected=$expected actual=$actual body=$(short_body "$file" | tr '\n' ' ' | cut -c1-700)"
  fi
}

assert_jwt_claim() {
  local token="$1"
  local claim="$2"
  local expected_regex="$3"
  local label="$4"
  local actual
  actual="$(python3 - "$token" "$claim" <<'PY'
import base64, json, sys
try:
    token, claim = sys.argv[1], sys.argv[2]
    p = token.split('.')[1]
    p += '=' * (-len(p) % 4)
    obj = json.loads(base64.urlsafe_b64decode(p.encode()))
    v = obj.get(claim, '')
    if isinstance(v, list):
        print(','.join(map(str, v)))
    else:
        print(v)
except Exception:
    print('')
PY
)"
  if printf '%s' "$actual" | grep -Eq "$expected_regex"; then
    record_pass "$label JWT claim $claim=$actual"
  else
    record_fail "$label JWT claim $claim" "expected regex '$expected_regex' but got '$actual'"
  fi
}

retry_request_to() {
  # retry_request_to <service> <base_url> <name> <method> <path> <expected> <body> <token>
  local service="$1" base="$2" name="$3" method="$4" path="$5" expected="$6" body="${7:-}" token="${8:-}"
  local attempt=1
  while [ "$attempt" -le "$AUTH_TEST_PROJECTION_RETRIES" ]; do
    if request_to "$service" "$base" "$name attempt $attempt" "$method" "$path" "$expected" "$body" "$token"; then
      return 0
    fi
    sleep "$AUTH_TEST_PROJECTION_SLEEP_SECONDS"
    attempt=$((attempt + 1))
  done
  return 1
}

print_header() {
  echo "${BOLD}${BLUE}Auth Service Full API + Integration Test${RESET}"
  echo "Auth Base URL:       $AUTH_BASE_URL"
  echo "Admin Base URL:      $ADMIN_BASE_URL"
  echo "User Base URL:       $USER_BASE_URL"
  echo "Calculator Base URL: $CALCULATOR_BASE_URL"
  echo "Todo Base URL:       $TODO_BASE_URL"
  echo "Report Base URL:     $REPORT_BASE_URL"
  echo "Tenant:              $AUTH_TEST_TENANT"
  echo "Timeout:             ${AUTH_TEST_TIMEOUT}s"
  echo "Run ID:              $RUN_ID"
  echo "Responses:           $TMP_DIR"
  echo
}

print_header

# -----------------------------------------------------------------------------
# Public Auth system endpoints
# -----------------------------------------------------------------------------
request_auth "hello" "GET" "/hello" "200" "" ""
assert_json_status auth hello ok
request_auth "health" "GET" "/health" "200|503" "" ""
HEALTH_FILE="$(last_file auth health)"
if [ -n "$HEALTH_FILE" ]; then
  HEALTH_STATUS="$(json_status "$HEALTH_FILE")"
  if [ "$AUTH_TEST_REQUIRE_HEALTH_OK" = "1" ] && [ "$HEALTH_STATUS" != "ok" ]; then
    record_fail "[auth] health status must be ok" "body=$(short_body "$HEALTH_FILE" | tr '\n' ' ' | cut -c1-1000)"
  elif [ "$HEALTH_STATUS" = "ok" ] || [ "$HEALTH_STATUS" = "down" ]; then
    record_pass "[auth] health uses canonical status field ($HEALTH_STATUS)"
  else
    record_fail "[auth] health canonical status" "actual=$HEALTH_STATUS"
  fi
fi
request_auth "docs" "GET" "/docs" "200" "" ""

request_auth "root rejected" "GET" "/" "404" "" ""
request_auth "live rejected" "GET" "/live" "404" "" ""
request_auth "ready rejected" "GET" "/ready" "404" "" ""
request_auth "healthy rejected" "GET" "/healthy" "404" "" ""
if [ "$AUTH_TEST_EXPECT_OPENAPI_PUBLIC" = "1" ]; then
  request_auth "openapi json public" "GET" "/openapi.json" "200" "" ""
else
  request_auth "openapi json rejected" "GET" "/openapi.json" "404" "" ""
fi

# -----------------------------------------------------------------------------
# Protected route auth failures and validation failures
# -----------------------------------------------------------------------------
request_auth "me without token" "GET" "/v1/me" "401" "" ""
request_auth "verify without token" "GET" "/v1/verify" "401" "" ""
request_auth "admin requests without token" "GET" "/v1/admin/requests" "401" "" ""
request_auth "me invalid token" "GET" "/v1/me" "401" "" "not-a-real-jwt"
request_auth "verify invalid token" "GET" "/v1/verify" "401" "" "not-a-real-jwt"

request_auth "signup invalid missing fields" "POST" "/v1/signup" "400|422" '{"username":"bad"}' ""
request_auth "signup invalid malformed json" "POST" "/v1/signup" "400|422" '{"username":' ""
request_auth "signin invalid credentials" "POST" "/v1/signin" "400|401|422" '{"username_or_email":"missing-user","password":"wrong"}' ""
request_auth "refresh invalid token" "POST" "/v1/token/refresh" "400|401|422" '{"refresh_token":"invalid-refresh-token"}' ""
request_auth "forgot invalid email" "POST" "/v1/password/forgot" "400|404|422" '{"email":"not-an-email"}' ""
request_auth "reset invalid token" "POST" "/v1/password/reset" "400|401|404|422" '{"reset_token":"invalid-reset-token","new_password":"Reset1234!Aa"}' ""
request_auth "change password without token" "POST" "/v1/password/change" "401" '{"current_password":"x","new_password":"Changed1234!Aa"}' ""
request_auth "admin register invalid missing reason" "POST" "/v1/admin/register" "400|422" '{"username":"badadmin","email":"badadmin@example.com","password":"Admin1234!Aa","full_name":"Bad Admin","birthdate":"1998-05-20","gender":"male"}' ""

# -----------------------------------------------------------------------------
# Signup normal user
# -----------------------------------------------------------------------------
SIGNUP_BODY=$(cat <<JSON
{
  "username": "$NORMAL_USERNAME",
  "email": "$NORMAL_EMAIL",
  "password": "$AUTH_TEST_INITIAL_PASSWORD",
  "full_name": "Auth Full Test User",
  "birthdate": "1998-05-20",
  "gender": "male",
  "account_type": "user"
}
JSON
)
request_auth "signup user" "POST" "/v1/signup" "200|201" "$SIGNUP_BODY" ""
SIGNUP_FILE="$(last_file auth "signup user")"
SIGNUP_ACCESS_TOKEN="$(json_get_any "$SIGNUP_FILE" "data.tokens.access_token" "data.access_token" "access_token")"
SIGNUP_REFRESH_TOKEN="$(json_get_any "$SIGNUP_FILE" "data.tokens.refresh_token" "data.refresh_token" "refresh_token")"
USER_ID="$(json_get_any "$SIGNUP_FILE" "data.user.id" "data.user.user_id" "data.id" "user.id")"
if [ -n "$SIGNUP_ACCESS_TOKEN" ] && [ -n "$SIGNUP_REFRESH_TOKEN" ] && [ -n "$USER_ID" ]; then
  record_pass "[auth] signup returned user id and token pair"
else
  record_fail "[auth] signup returned user id and token pair" "user_id=$USER_ID access_token_present=$([ -n "$SIGNUP_ACCESS_TOKEN" ] && echo yes || echo no) refresh_token_present=$([ -n "$SIGNUP_REFRESH_TOKEN" ] && echo yes || echo no)"
fi

request_auth "signup duplicate user" "POST" "/v1/signup" "400|409|422" "$SIGNUP_BODY" ""

# -----------------------------------------------------------------------------
# Signin and JWT claims
# -----------------------------------------------------------------------------
SIGNIN_BODY=$(cat <<JSON
{
  "username_or_email": "$NORMAL_USERNAME",
  "password": "$AUTH_TEST_INITIAL_PASSWORD",
  "device_id": "auth-full-test"
}
JSON
)
request_auth "signin" "POST" "/v1/signin" "200" "$SIGNIN_BODY" ""
SIGNIN_FILE="$(last_file auth signin)"
ACCESS_TOKEN="$(json_get_any "$SIGNIN_FILE" "data.tokens.access_token" "data.access_token" "access_token")"
REFRESH_TOKEN="$(json_get_any "$SIGNIN_FILE" "data.tokens.refresh_token" "data.refresh_token" "refresh_token")"
if [ -n "$ACCESS_TOKEN" ] && [ -n "$REFRESH_TOKEN" ]; then
  record_pass "[auth] signin returned token pair"
  assert_jwt_claim "$ACCESS_TOKEN" iss '^auth$' "normal user"
  assert_jwt_claim "$ACCESS_TOKEN" aud '(^micro-app$|.*micro-app.*)' "normal user"
  assert_jwt_claim "$ACCESS_TOKEN" sub '.+' "normal user"
  assert_jwt_claim "$ACCESS_TOKEN" jti '.+' "normal user"
  assert_jwt_claim "$ACCESS_TOKEN" role '^user$' "normal user"
  assert_jwt_claim "$ACCESS_TOKEN" tenant "^${AUTH_TEST_TENANT}$" "normal user"
else
  record_fail "[auth] signin returned token pair" "missing access_token or refresh_token"
fi

request_auth "signin wrong password" "POST" "/v1/signin" "400|401" "{\"username_or_email\":\"$NORMAL_USERNAME\",\"password\":\"wrong\",\"device_id\":\"auth-full-test\"}" ""
request_auth "login alias" "POST" "/v1/login" "200" "$SIGNIN_BODY" ""
LOGIN_FILE="$(last_file auth "login alias")"
LOGIN_ACCESS_TOKEN="$(json_get_any "$LOGIN_FILE" "data.tokens.access_token" "data.access_token" "access_token")"
LOGIN_REFRESH_TOKEN="$(json_get_any "$LOGIN_FILE" "data.tokens.refresh_token" "data.refresh_token" "refresh_token")"
if [ -n "$LOGIN_ACCESS_TOKEN" ]; then ACCESS_TOKEN="$LOGIN_ACCESS_TOKEN"; fi
if [ -n "$LOGIN_REFRESH_TOKEN" ]; then REFRESH_TOKEN="$LOGIN_REFRESH_TOKEN"; fi

if [ -n "$ACCESS_TOKEN" ]; then
  request_auth "me with token" "GET" "/v1/me" "200" "" "$ACCESS_TOKEN"
  request_auth "verify token" "GET" "/v1/verify" "200" "" "$ACCESS_TOKEN"
  request_auth "admin requests with normal user" "GET" "/v1/admin/requests" "403" "" "$ACCESS_TOKEN"
else
  record_skip "[auth] me with token" "no access token available"
  record_skip "[auth] verify token" "no access token available"
  record_skip "[auth] admin requests with normal user" "no access token available"
fi

# -----------------------------------------------------------------------------
# Refresh rotation
# -----------------------------------------------------------------------------
OLD_REFRESH_TOKEN="$REFRESH_TOKEN"
if [ -n "$REFRESH_TOKEN" ]; then
  REFRESH_BODY="{\"refresh_token\":\"$REFRESH_TOKEN\"}"
  request_auth "refresh token" "POST" "/v1/token/refresh" "200" "$REFRESH_BODY" ""
  REFRESH_FILE="$(last_file auth "refresh token")"
  NEW_ACCESS_TOKEN="$(json_get_any "$REFRESH_FILE" "data.tokens.access_token" "data.access_token" "access_token")"
  NEW_REFRESH_TOKEN="$(json_get_any "$REFRESH_FILE" "data.tokens.refresh_token" "data.refresh_token" "refresh_token")"
  if [ -n "$NEW_ACCESS_TOKEN" ]; then ACCESS_TOKEN="$NEW_ACCESS_TOKEN"; fi
  if [ -n "$NEW_REFRESH_TOKEN" ]; then REFRESH_TOKEN="$NEW_REFRESH_TOKEN"; fi
  if [ -n "$OLD_REFRESH_TOKEN" ]; then
    request_auth "reuse old refresh token" "POST" "/v1/token/refresh" "400|401|409|422" "{\"refresh_token\":\"$OLD_REFRESH_TOKEN\"}" ""
  fi
else
  record_skip "[auth] refresh token" "no refresh token available"
fi

# -----------------------------------------------------------------------------
# Password forgot/reset/change
# -----------------------------------------------------------------------------
request_auth "password forgot" "POST" "/v1/password/forgot" "200" "{\"email\":\"$NORMAL_EMAIL\"}" ""
FORGOT_FILE="$(last_file auth "password forgot")"
RESET_TOKEN="$(json_get_any "$FORGOT_FILE" "data.reset_token" "data.token" "reset_token")"
CURRENT_PASSWORD="$AUTH_TEST_INITIAL_PASSWORD"

if [ -n "$RESET_TOKEN" ]; then
  request_auth "password reset" "POST" "/v1/password/reset" "200" "{\"reset_token\":\"$RESET_TOKEN\",\"new_password\":\"$AUTH_TEST_RESET_PASSWORD\"}" ""
  CURRENT_PASSWORD="$AUTH_TEST_RESET_PASSWORD"
  request_auth "signin old password after reset" "POST" "/v1/signin" "400|401" "{\"username_or_email\":\"$NORMAL_USERNAME\",\"password\":\"$AUTH_TEST_INITIAL_PASSWORD\",\"device_id\":\"auth-full-test-old-password\"}" ""
  request_auth "signin after password reset" "POST" "/v1/signin" "200" "{\"username_or_email\":\"$NORMAL_USERNAME\",\"password\":\"$CURRENT_PASSWORD\",\"device_id\":\"auth-full-test-after-reset\"}" ""
  SIGNIN_RESET_FILE="$(last_file auth "signin after password reset")"
  ACCESS_TOKEN="$(json_get_any "$SIGNIN_RESET_FILE" "data.tokens.access_token" "data.access_token" "access_token")"
else
  if [ "$AUTH_TEST_EXPECT_RESET_TOKEN" = "1" ]; then
    record_fail "[auth] password forgot returned reset token" "expected reset token in response but none was found"
  else
    record_skip "[auth] password reset" "no reset_token returned. This is normal in stage/prod; set AUTH_TEST_EXPECT_RESET_TOKEN=1 if dev must expose it."
  fi
fi

if [ -n "$ACCESS_TOKEN" ]; then
  request_auth "password change wrong current" "POST" "/v1/password/change" "400|401|422" "{\"current_password\":\"wrong\",\"new_password\":\"$AUTH_TEST_CHANGED_PASSWORD\"}" "$ACCESS_TOKEN"
  request_auth "password change" "POST" "/v1/password/change" "200" "{\"current_password\":\"$CURRENT_PASSWORD\",\"new_password\":\"$AUTH_TEST_CHANGED_PASSWORD\"}" "$ACCESS_TOKEN"
  CURRENT_PASSWORD="$AUTH_TEST_CHANGED_PASSWORD"
  request_auth "signin after password change" "POST" "/v1/signin" "200" "{\"username_or_email\":\"$NORMAL_USERNAME\",\"password\":\"$CURRENT_PASSWORD\",\"device_id\":\"auth-full-test-after-change\"}" ""
  SIGNIN_CHANGED_FILE="$(last_file auth "signin after password change")"
  ACCESS_TOKEN="$(json_get_any "$SIGNIN_CHANGED_FILE" "data.tokens.access_token" "data.access_token" "access_token")"
  REFRESH_TOKEN="$(json_get_any "$SIGNIN_CHANGED_FILE" "data.tokens.refresh_token" "data.refresh_token" "refresh_token")"
else
  record_skip "[auth] password change" "no access token available"
fi

# -----------------------------------------------------------------------------
# Bootstrap admin and admin-only auth APIs
# -----------------------------------------------------------------------------
BOOTSTRAP_ADMIN_BODY=$(cat <<JSON
{
  "username_or_email": "$AUTH_TEST_ADMIN_USERNAME",
  "password": "$AUTH_TEST_ADMIN_PASSWORD",
  "device_id": "auth-full-test-admin"
}
JSON
)
request_auth "bootstrap admin signin" "POST" "/v1/signin" "200" "$BOOTSTRAP_ADMIN_BODY" ""
BOOTSTRAP_ADMIN_FILE="$(last_file auth "bootstrap admin signin")"
ADMIN_TOKEN="$(json_get_any "$BOOTSTRAP_ADMIN_FILE" "data.tokens.access_token" "data.access_token" "access_token")"
ADMIN_ID="$(json_get_any "$BOOTSTRAP_ADMIN_FILE" "data.user.id" "data.user.user_id" "data.id" "user.id")"
ADMIN_ROLE="$(json_get_any "$BOOTSTRAP_ADMIN_FILE" "data.user.role" "role")"
ADMIN_STATUS="$(json_get_any "$BOOTSTRAP_ADMIN_FILE" "data.user.admin_status" "admin_status")"
if [ -n "$ADMIN_TOKEN" ]; then
  assert_jwt_claim "$ADMIN_TOKEN" role '^admin$' "bootstrap admin"
  assert_jwt_claim "$ADMIN_TOKEN" admin_status '^approved$' "bootstrap admin"
  assert_jwt_claim "$ADMIN_TOKEN" tenant "^${AUTH_TEST_TENANT}$" "bootstrap admin"
  if [ "$ADMIN_ROLE" = "admin" ] && [ "$ADMIN_STATUS" = "approved" ]; then
    record_pass "[auth] bootstrap admin response is approved admin"
  else
    record_warn "[auth] bootstrap admin response role/status" "role=$ADMIN_ROLE admin_status=$ADMIN_STATUS; JWT claims were checked separately"
  fi
  request_auth "list admin requests" "GET" "/v1/admin/requests" "200" "" "$ADMIN_TOKEN"
else
  record_fail "[auth] bootstrap admin signin returned admin token" "Set AUTH_TEST_ADMIN_USERNAME/AUTH_TEST_ADMIN_PASSWORD if defaults differ."
fi

# -----------------------------------------------------------------------------
# Admin registration approval and rejection
# -----------------------------------------------------------------------------
ADMIN_REGISTER_BODY=$(cat <<JSON
{
  "username": "$PENDING_ADMIN_USERNAME",
  "email": "$PENDING_ADMIN_EMAIL",
  "password": "$AUTH_TEST_PENDING_ADMIN_PASSWORD",
  "full_name": "Auth Full Test Pending Admin",
  "birthdate": "1998-05-20",
  "gender": "male",
  "account_type": "admin",
  "reason": "I need admin access to verify the auth service admin approval flow."
}
JSON
)
request_auth "admin register request" "POST" "/v1/admin/register" "200|201" "$ADMIN_REGISTER_BODY" ""
ADMIN_REGISTER_FILE="$(last_file auth "admin register request")"
PENDING_ADMIN_ID="$(json_get_any "$ADMIN_REGISTER_FILE" "data.user.id" "data.user.user_id" "data.id" "user.id")"
if [ -n "$PENDING_ADMIN_ID" ]; then
  record_pass "[auth] admin register returned pending admin id"
else
  record_fail "[auth] admin register returned pending admin id" "missing user id"
fi

if [ -n "$PENDING_ADMIN_ID" ]; then
  PENDING_ADMIN_SIGNIN_BODY="{\"username_or_email\":\"$PENDING_ADMIN_USERNAME\",\"password\":\"$AUTH_TEST_PENDING_ADMIN_PASSWORD\",\"device_id\":\"auth-full-test-pending-admin\"}"
  request_auth "pending admin signin" "POST" "/v1/signin" "200" "$PENDING_ADMIN_SIGNIN_BODY" ""
  PENDING_ADMIN_SIGNIN_FILE="$(last_file auth "pending admin signin")"
  PENDING_ADMIN_TOKEN="$(json_get_any "$PENDING_ADMIN_SIGNIN_FILE" "data.tokens.access_token" "data.access_token" "access_token")"
  if [ -n "$PENDING_ADMIN_TOKEN" ]; then
    assert_jwt_claim "$PENDING_ADMIN_TOKEN" role '^admin$' "pending admin"
    assert_jwt_claim "$PENDING_ADMIN_TOKEN" admin_status '^pending$' "pending admin"
    request_auth "admin requests with pending admin" "GET" "/v1/admin/requests" "403" "" "$PENDING_ADMIN_TOKEN"
  fi
fi

if [ -n "${ADMIN_TOKEN:-}" ] && [ -n "$PENDING_ADMIN_ID" ]; then
  request_auth "admin decision invalid body" "POST" "/v1/admin/requests/$PENDING_ADMIN_ID/decision" "400|422" '{"decision":"invalid"}' "$ADMIN_TOKEN"
  request_auth "admin request approve decision" "POST" "/v1/admin/requests/$PENDING_ADMIN_ID/decision" "200" '{"decision":"approve","reason":"Approved by auth full API test."}' "$ADMIN_TOKEN"
  request_auth "approved admin can signin" "POST" "/v1/signin" "200" "{\"username_or_email\":\"$PENDING_ADMIN_USERNAME\",\"password\":\"$AUTH_TEST_PENDING_ADMIN_PASSWORD\",\"device_id\":\"auth-full-test-approved-admin\"}" ""
  APPROVED_ADMIN_FILE="$(last_file auth "approved admin can signin")"
  APPROVED_ADMIN_TOKEN="$(json_get_any "$APPROVED_ADMIN_FILE" "data.tokens.access_token" "data.access_token" "access_token")"
  APPROVED_ADMIN_STATUS="$(json_get_any "$APPROVED_ADMIN_FILE" "data.user.admin_status" "admin_status")"
  if [ "$APPROVED_ADMIN_STATUS" = "approved" ]; then
    record_pass "[auth] approved admin signin shows admin_status=approved"
  else
    record_fail "[auth] approved admin signin shows admin_status=approved" "actual=$APPROVED_ADMIN_STATUS"
  fi
  if [ -n "$APPROVED_ADMIN_TOKEN" ]; then
    request_auth "approved admin list admin requests" "GET" "/v1/admin/requests" "200" "" "$APPROVED_ADMIN_TOKEN"
  fi
fi

REJECT_REGISTER_BODY=$(cat <<JSON
{
  "username": "$REJECT_ADMIN_USERNAME",
  "email": "$REJECT_ADMIN_EMAIL",
  "password": "$AUTH_TEST_PENDING_ADMIN_PASSWORD",
  "full_name": "Auth Full Test Rejected Admin",
  "birthdate": "1998-05-20",
  "gender": "male",
  "account_type": "admin",
  "reason": "This request should be rejected by the auth full API test."
}
JSON
)
request_auth "admin register reject request" "POST" "/v1/admin/register" "200|201" "$REJECT_REGISTER_BODY" ""
REJECT_REGISTER_FILE="$(last_file auth "admin register reject request")"
REJECT_ADMIN_ID="$(json_get_any "$REJECT_REGISTER_FILE" "data.user.id" "data.user.user_id" "data.id" "user.id")"
if [ -n "${ADMIN_TOKEN:-}" ] && [ -n "$REJECT_ADMIN_ID" ]; then
  request_auth "admin request reject decision" "POST" "/v1/admin/requests/$REJECT_ADMIN_ID/decision" "200" '{"decision":"reject","reason":"Rejected by auth full API test."}' "$ADMIN_TOKEN"
  request_auth "rejected admin signin" "POST" "/v1/signin" "200|403" "{\"username_or_email\":\"$REJECT_ADMIN_USERNAME\",\"password\":\"$AUTH_TEST_PENDING_ADMIN_PASSWORD\",\"device_id\":\"auth-full-test-rejected-admin\"}" ""
fi

# -----------------------------------------------------------------------------
# Logout and revoked token checks
# -----------------------------------------------------------------------------
if [ -n "${ACCESS_TOKEN:-}" ]; then
  TOKEN_TO_REVOKE="$ACCESS_TOKEN"
  request_auth "logout" "POST" "/v1/logout" "200" "" "$TOKEN_TO_REVOKE"
  request_auth "me with revoked token" "GET" "/v1/me" "401" "" "$TOKEN_TO_REVOKE"
  request_auth "verify revoked token" "GET" "/v1/verify" "401" "" "$TOKEN_TO_REVOKE"
else
  record_skip "[auth] logout" "no user access token available"
fi

# -----------------------------------------------------------------------------
# Optional downstream service communication checks
# -----------------------------------------------------------------------------
if [ "$AUTH_TEST_DOWNSTREAM_ENABLED" = "1" ]; then
  echo
  echo "${BOLD}${BLUE}Downstream JWT and projection checks${RESET}"

  if [ -n "${ADMIN_TOKEN:-}" ]; then
    request_to admin "$ADMIN_BASE_URL" "hello" "GET" "/hello" "200" "" ""
    request_to admin "$ADMIN_BASE_URL" "dashboard with admin token" "GET" "/v1/admin/dashboard" "200" "" "$ADMIN_TOKEN"
    request_to admin "$ADMIN_BASE_URL" "summary with admin token" "GET" "/v1/admin/summary" "200" "" "$ADMIN_TOKEN"
    request_to admin "$ADMIN_BASE_URL" "dashboard without token" "GET" "/v1/admin/dashboard" "401" "" ""
    if [ -n "${SIGNUP_ACCESS_TOKEN:-}" ]; then
      request_to admin "$ADMIN_BASE_URL" "dashboard with normal user token" "GET" "/v1/admin/dashboard" "403" "" "$SIGNUP_ACCESS_TOKEN"
    fi
    if [ -n "$USER_ID" ]; then
      retry_request_to admin "$ADMIN_BASE_URL" "user projection" "GET" "/v1/admin/users/$USER_ID" "200|404" "" "$ADMIN_TOKEN" || true
    fi
  else
    record_skip "[admin] admin JWT checks" "no approved admin token available"
  fi

  if [ -n "${SIGNUP_ACCESS_TOKEN:-}" ]; then
    request_to user "$USER_BASE_URL" "hello" "GET" "/hello" "200|404|000" "" "" || true
    request_to user "$USER_BASE_URL" "me with auth token" "GET" "/v1/users/me" "200|404" "" "$SIGNUP_ACCESS_TOKEN" || true
    request_to user "$USER_BASE_URL" "me without token" "GET" "/v1/users/me" "401" "" "" || true
    request_to calculator "$CALCULATOR_BASE_URL" "hello" "GET" "/hello" "200|404|000" "" "" || true
    request_to calculator "$CALCULATOR_BASE_URL" "operations with auth token" "GET" "/v1/calculator/operations" "200" "" "$SIGNUP_ACCESS_TOKEN" || true
    request_to calculator "$CALCULATOR_BASE_URL" "operations without token" "GET" "/v1/calculator/operations" "401" "" "" || true
    request_to todo "$TODO_BASE_URL" "hello" "GET" "/hello" "200|404|000" "" "" || true
    request_to todo "$TODO_BASE_URL" "todos list with auth token" "GET" "/v1/todos" "200" "" "$SIGNUP_ACCESS_TOKEN" || true
    request_to todo "$TODO_BASE_URL" "todos without token" "GET" "/v1/todos" "401" "" "" || true
    request_to report "$REPORT_BASE_URL" "hello" "GET" "/hello" "200|404|000" "" "" || true
    request_to report "$REPORT_BASE_URL" "report types with auth token" "GET" "/v1/reports/types" "200" "" "$SIGNUP_ACCESS_TOKEN" || true
    request_to report "$REPORT_BASE_URL" "report types without token" "GET" "/v1/reports/types" "401" "" "" || true

    if [ "$AUTH_TEST_DOWNSTREAM_MUTATE" = "1" ]; then
      CALC_BODY='{"operation":"ADD","operands":[10,20]}'
      request_to calculator "$CALCULATOR_BASE_URL" "calculate add" "POST" "/v1/calculator/calculate" "200|201" "$CALC_BODY" "$SIGNUP_ACCESS_TOKEN" || true
      TODO_BODY=$(cat <<JSON
{
  "title": "Auth integration todo $RUN_ID",
  "description": "Created by auth service full integration test.",
  "priority": "MEDIUM",
  "due_date": "$(iso_utc_days_from_now 3)",
  "tags": ["auth-test", "integration"]
}
JSON
)
      request_to todo "$TODO_BASE_URL" "create todo" "POST" "/v1/todos" "200|201" "$TODO_BODY" "$SIGNUP_ACCESS_TOKEN" || true
      REPORT_BODY=$(cat <<JSON
{
  "report_type": "calculator_history_report",
  "format": "json",
  "date_from": "$(today_date_utc)",
  "date_to": "$(today_date_utc)",
  "filters": {},
  "options": {}
}
JSON
)
      request_to report "$REPORT_BASE_URL" "create report" "POST" "/v1/reports" "200|201|202" "$REPORT_BODY" "$SIGNUP_ACCESS_TOKEN" || true
    fi
  else
    record_skip "[downstream] normal JWT checks" "no normal user access token available"
  fi
else
  record_skip "[downstream] service communication checks" "AUTH_TEST_DOWNSTREAM_ENABLED=0"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo
printf "%sSummary:%s %s total, %s passed, %s failed, %s skipped, %s warnings\n" "$BOLD" "$RESET" "$TEST_COUNT" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$WARN_COUNT"
echo "Normal user:         $NORMAL_USERNAME / $NORMAL_EMAIL"
echo "Pending admin user:  $PENDING_ADMIN_USERNAME / $PENDING_ADMIN_EMAIL"
echo "Rejected admin user: $REJECT_ADMIN_USERNAME / $REJECT_ADMIN_EMAIL"
echo "Auth Base URL:       $AUTH_BASE_URL"
echo "Response directory:  $TMP_DIR"

if [ "$AUTH_TEST_SAVE_RESPONSES" != "1" ] && [ "$CLEAN_TMP" = "1" ]; then
  echo "Response files are temporary and will be removed on exit. Set AUTH_TEST_SAVE_RESPONSES=1 and AUTH_TEST_RESPONSE_DIR=./responses to keep them."
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo
  echo "One or more auth service checks failed. Review the failure messages above."
  exit 1
fi

echo
printf "%sAll required auth service checks passed.%s\n" "$GREEN" "$RESET"
exit 0
