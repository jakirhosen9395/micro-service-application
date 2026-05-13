#!/usr/bin/env bash
# User Service full API + integration smoke/contract test.
#
# Usage:
#   chmod +x user_service_full_api_test.sh
#   cp user_service_full_api_test.env.example user_service_full_api_test.env
#   ./user_service_full_api_test.sh ./user_service_full_api_test.env
#
# This script is intentionally env-file based so dev/stage/prod can be tested
# without editing the script.

set -u

ENV_FILE="${1:-./user_service_full_api_test.env}"

usage() {
  cat <<'USAGE'
Usage:
  ./user_service_full_api_test.sh <env-file>

Example:
  cp user_service_full_api_test.env.example user_service_full_api_test.env
  chmod +x user_service_full_api_test.sh
  ./user_service_full_api_test.sh ./user_service_full_api_test.env

Required env values:
  USER_BASE_URL
  AUTH_BASE_URL

Optional cross-service env values:
  CALCULATOR_BASE_URL
  TODO_BASE_URL
  ADMIN_BASE_URL
  REPORT_BASE_URL

Exit codes:
  0 = all required checks passed
  1 = at least one required check failed
  2 = invalid usage or missing local command
USAGE
}

if [ "${ENV_FILE:-}" = "-h" ] || [ "${ENV_FILE:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Env file not found: $ENV_FILE"
  usage
  exit 2
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

USER_BASE_URL="${USER_BASE_URL:-}"
AUTH_BASE_URL="${AUTH_BASE_URL:-}"
CALCULATOR_BASE_URL="${CALCULATOR_BASE_URL:-}"
TODO_BASE_URL="${TODO_BASE_URL:-}"
ADMIN_BASE_URL="${ADMIN_BASE_URL:-}"
REPORT_BASE_URL="${REPORT_BASE_URL:-}"

if [ -z "$USER_BASE_URL" ]; then
  echo "USER_BASE_URL is required in $ENV_FILE"
  exit 2
fi

if [ -z "$AUTH_BASE_URL" ] && [ -z "${USER_TEST_ACCESS_TOKEN:-}" ]; then
  echo "AUTH_BASE_URL is required unless USER_TEST_ACCESS_TOKEN is provided."
  exit 2
fi

USER_BASE_URL="${USER_BASE_URL%/}"
AUTH_BASE_URL="${AUTH_BASE_URL%/}"
CALCULATOR_BASE_URL="${CALCULATOR_BASE_URL%/}"
TODO_BASE_URL="${TODO_BASE_URL%/}"
ADMIN_BASE_URL="${ADMIN_BASE_URL%/}"
REPORT_BASE_URL="${REPORT_BASE_URL%/}"

TIMEOUT="${USER_TEST_TIMEOUT:-20}"
REQUEST_RETRIES="${USER_TEST_RETRIES:-2}"
RETRY_DELAY_SECONDS="${USER_TEST_RETRY_DELAY_SECONDS:-2}"
VERBOSE="${USER_TEST_VERBOSE:-0}"
SAVE_RESPONSES="${USER_TEST_SAVE_RESPONSES:-0}"
CREATE_USER="${USER_TEST_CREATE_USER:-1}"
CREATE_SECOND_USER="${USER_TEST_CREATE_SECOND_USER:-1}"
AUTH_LOGIN_PATH="${USER_TEST_AUTH_LOGIN_PATH:-/v1/signin}"
RUN_MUTATIONS="${USER_TEST_MUTATE:-1}"
SEED_CALCULATOR="${USER_TEST_SEED_CALCULATOR:-1}"
SEED_TODO="${USER_TEST_SEED_TODO:-1}"
SEED_REPORT="${USER_TEST_SEED_REPORT:-1}"
STRICT_PUBLIC_ROUTES="${USER_TEST_STRICT_PUBLIC_ROUTES:-1}"
EXPECT_EXTENDED_USER_ENDPOINTS="${USER_TEST_EXPECT_EXTENDED_USER_ENDPOINTS:-1}"
REQUIRED_CODE_COVERAGE="${USER_TEST_REQUIRED_CODE_COVERAGE:-1}"
ACCESS_REQUEST_TTL_DAYS="${USER_TEST_ACCESS_REQUEST_TTL_DAYS:-14}"

USER_FORWARDED_PROTO="${USER_FORWARDED_PROTO:-}"
AUTH_FORWARDED_PROTO="${AUTH_FORWARDED_PROTO:-}"
CALCULATOR_FORWARDED_PROTO="${CALCULATOR_FORWARDED_PROTO:-}"
TODO_FORWARDED_PROTO="${TODO_FORWARDED_PROTO:-}"
ADMIN_FORWARDED_PROTO="${ADMIN_FORWARDED_PROTO:-}"
REPORT_FORWARDED_PROTO="${REPORT_FORWARDED_PROTO:-}"

ADMIN_USERNAME="${USER_TEST_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${USER_TEST_ADMIN_PASSWORD:-admin123}"
ACCESS_TOKEN="${USER_TEST_ACCESS_TOKEN:-}"
SECOND_TOKEN="${USER_TEST_SECOND_TOKEN:-}"
ADMIN_TOKEN="${USER_TEST_ADMIN_TOKEN:-}"

RUN_ID="$(date +%s)-$RANDOM"
TEST_USERNAME="${USER_TEST_USERNAME:-userapi_${RUN_ID}}"
TEST_EMAIL="${USER_TEST_EMAIL:-${TEST_USERNAME}@example.com}"
TEST_PASSWORD="${USER_TEST_PASSWORD:-Test1234!Aa}"
SECOND_USERNAME="${USER_TEST_SECOND_USERNAME:-userapi_other_${RUN_ID}}"
SECOND_EMAIL="${USER_TEST_SECOND_EMAIL:-${SECOND_USERNAME}@example.com}"
SECOND_PASSWORD="${USER_TEST_SECOND_PASSWORD:-Test1234!Aa}"

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
ACCESS_REQUEST_ID=""
ACCESS_GRANT_ID=""
CALCULATION_ID=""
TODO_ID=""
REPORT_ID=""
REPORT_SERVICE_REPORT_ID=""

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

safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_'
}

future_rfc3339_days() {
  python3 - "$1" <<'PY'
from datetime import datetime, timezone, timedelta
import sys
days = int(sys.argv[1])
print((datetime.now(timezone.utc) + timedelta(days=days)).replace(microsecond=0).isoformat().replace('+00:00', 'Z'))
PY
}

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
token, claim = sys.argv[1], sys.argv[2]
try:
    payload = token.split('.')[1]
    payload += '=' * (-len(payload) % 4)
    obj = json.loads(base64.urlsafe_b64decode(payload.encode()).decode())
    val = obj.get(claim, '')
    print(json.dumps(val, separators=(',', ':')) if isinstance(val, (dict, list)) else val)
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
        sensitive_words = ('token', 'secret', 'password', 'authorization', 'access_key', 'refresh', 'jwt')
        def redact(x):
            if isinstance(x, dict):
                return {k: ('<redacted>' if any(w in k.lower() for w in sensitive_words) else redact(v)) for k, v in x.items()}
            if isinstance(x, list):
                return [redact(i) for i in x]
            return x
        print(json.dumps(redact(obj), indent=2)[:2200])
    except Exception:
        print(data[:2200])
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
  if [ "${2:-}" != "" ]; then echo "       $2"; fi
}

record_skip() {
  TEST_COUNT=$((TEST_COUNT + 1)); SKIP_COUNT=$((SKIP_COUNT + 1))
  printf "%s[SKIP]%s %s\n" "$YELLOW" "$RESET" "$1"
  if [ "${2:-}" != "" ]; then echo "       $2"; fi
}

remember_code() {
  case " $OBSERVED_CODES " in *" $1 "*) ;; *) OBSERVED_CODES="$OBSERVED_CODES $1" ;; esac
}

is_retryable_code() {
  case "$1" in 000|408|425|429|500|502|503|504) return 0 ;; *) return 1 ;; esac
}

last_file() {
  cat "$TMP_DIR/$(safe_name "$1").path" 2>/dev/null || true
}

last_code() {
  cat "$TMP_DIR/$(safe_name "$1").code" 2>/dev/null || true
}

validate_json_envelope() {
  local file="$1" code="$2" path="$3"
  python3 - "$file" "$code" "$path" <<'PY'
import json, sys
file_path, code, path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
try:
    obj = json.load(open(file_path, 'r', encoding='utf-8'))
except Exception as e:
    print(f'not valid JSON: {e}')
    sys.exit(1)

if path in ('/hello', '/health') and code < 400:
    if obj.get('status') in ('ok', 'down'):
        sys.exit(0)
    print('system endpoint response missing status ok/down')
    sys.exit(1)

if code >= 400:
    required = ['status', 'message', 'error_code', 'details', 'path', 'request_id', 'trace_id', 'timestamp']
    missing = [k for k in required if k not in obj]
    if missing or obj.get('status') != 'error':
        print(f'bad error envelope missing={missing} status={obj.get("status")}')
        sys.exit(1)
else:
    required = ['status', 'message', 'data', 'request_id', 'trace_id', 'timestamp']
    missing = [k for k in required if k not in obj]
    if missing or obj.get('status') != 'ok':
        print(f'bad success envelope missing={missing} status={obj.get("status")}')
        sys.exit(1)
PY
}

assert_json_status_ok() {
  local name="$1" file status
  file="$(last_file "$name")"
  status="$(json_status "$file")"
  if [ "$status" = "ok" ]; then
    record_pass "$name envelope status is ok"
  else
    record_fail "$name envelope status" "expected status=ok, got '$status'. Body: $(short_body "$file" | tr '\n' ' ' | cut -c1-1000)"
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
    record_fail "$name error envelope" "expected status=error and error_code=$expected_error, got status=$status error_code=$error_code. Body: $(short_body "$file" | tr '\n' ' ' | cut -c1-1000)"
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
    print(str(exc))
    sys.exit(1)
PY
  rc=$?
  if [ "$rc" -eq 0 ]; then
    record_pass "$name health dependency shape"
  else
    record_fail "$name health dependency shape" "$(short_body "$file" | tr '\n' ' ' | cut -c1-1000)"
  fi
}

request_base() {
  # request_base <base_url> <forwarded_proto> <name> <method> <path> <expected_codes_regex> <body_or_empty> <bearer_token_or_empty> <envelope:json|html|none>
  local base_url="$1" forwarded_proto="$2" name="$3" method="$4" path="$5" expected="$6" body="${7:-}" token="${8:-}" envelope="${9:-json}"
  local safe outfile req_id trace_id accept_header http_code curl_exit attempt response_summary
  safe="$(safe_name "$name")"
  outfile="$TMP_DIR/${safe}.json"
  req_id="req-$(new_uuid | tr -d '-')"
  trace_id="trace-$(new_uuid | tr -d '-')"
  accept_header="application/json"
  [ "$envelope" = "html" ] && accept_header="text/html,application/xhtml+xml,*/*"

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

    if [ "$forwarded_proto" != "" ]; then
      curl_args+=( -H "X-Forwarded-Proto: $forwarded_proto" )
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

    if [ "$VERBOSE" = "1" ]; then
      echo "--- $name attempt $attempt response ($http_code) ---"
      short_body "$outfile"
      echo "----------------------------------------------"
    fi

    if [ "$curl_exit" -eq 0 ] && printf '%s' "$http_code" | grep -Eq "^($expected)$"; then
      remember_code "$http_code"
      if [ "$envelope" = "json" ]; then
        if ! err="$(validate_json_envelope "$outfile" "$http_code" "$path" 2>&1)"; then
          record_fail "$name envelope" "$err; body: $(short_body "$outfile" | tr '\n' ' ' | cut -c1-1200)"
          return 1
        fi
      fi
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
  response_summary="$(short_body "$outfile" | tr '\n' ' ' | cut -c1-1200)"
  if [ "$curl_exit" -ne 0 ]; then
    record_fail "$name ($method $path curl failed after $attempt attempt(s))" "$(cat "$outfile.curlerr" 2>/dev/null)"
  else
    record_fail "$name ($method $path expected HTTP $expected but got $http_code after $attempt attempt(s))" "response: $response_summary"
  fi
  return 1
}

user_request() { request_base "$USER_BASE_URL" "$USER_FORWARDED_PROTO" "$@"; }
auth_request() { request_base "$AUTH_BASE_URL" "$AUTH_FORWARDED_PROTO" "$@"; }
calc_request() { request_base "$CALCULATOR_BASE_URL" "$CALCULATOR_FORWARDED_PROTO" "$@"; }
todo_request() { request_base "$TODO_BASE_URL" "$TODO_FORWARDED_PROTO" "$@"; }
admin_request() { request_base "$ADMIN_BASE_URL" "$ADMIN_FORWARDED_PROTO" "$@"; }
report_request() { request_base "$REPORT_BASE_URL" "$REPORT_FORWARDED_PROTO" "$@"; }

print_section() {
  printf "\n%s%s%s\n" "$BOLD" "$1" "$RESET"
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
  auth_request "auth signup $username" "POST" "/v1/signup" "200|201|409" "$body" "" "json"
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
  auth_request "$name" "POST" "$AUTH_LOGIN_PATH" "200" "$body" "" "json"
}

login_primary_user() {
  if [ "$ACCESS_TOKEN" != "" ]; then
    USER_ID="$(jwt_claim "$ACCESS_TOKEN" "sub")"
    record_pass "primary user token provided by USER_TEST_ACCESS_TOKEN"
    [ "$USER_ID" != "" ] && record_pass "primary user id extracted from JWT: $USER_ID" || record_fail "primary user id extracted" "JWT sub unavailable"
    return 0
  fi

  if [ "$CREATE_USER" = "1" ]; then
    signup_user "$TEST_USERNAME" "$TEST_EMAIL" "$TEST_PASSWORD" "User Service Full API Test User"
  fi

  signin_user "$TEST_USERNAME" "$TEST_PASSWORD" "user-service-full-$RUN_ID" "auth primary user signin"
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
    record_pass "second user token provided by USER_TEST_SECOND_TOKEN"
    [ "$SECOND_USER_ID" != "" ] && record_pass "second user id extracted from JWT: $SECOND_USER_ID" || record_skip "second user id extracted" "JWT sub unavailable"
    return 0
  fi

  if [ "$CREATE_SECOND_USER" != "1" ] || [ "$AUTH_BASE_URL" = "" ]; then
    record_skip "second user login" "USER_TEST_CREATE_SECOND_USER is not 1 or AUTH_BASE_URL missing"
    return 0
  fi

  signup_user "$SECOND_USERNAME" "$SECOND_EMAIL" "$SECOND_PASSWORD" "User Service Full API Second User"
  signin_user "$SECOND_USERNAME" "$SECOND_PASSWORD" "user-service-full-second-$RUN_ID" "auth second user signin"
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
    record_pass "admin token provided by USER_TEST_ADMIN_TOKEN"
    return 0
  fi

  if [ "$AUTH_BASE_URL" = "" ]; then
    record_skip "admin token" "AUTH_BASE_URL missing"
    return 0
  fi

  local body file role admin_status
  body=$(cat <<JSON
{
  "username_or_email": "$ADMIN_USERNAME",
  "password": "$ADMIN_PASSWORD",
  "device_id": "user-service-full-admin-$RUN_ID"
}
JSON
)
  auth_request "auth admin signin" "POST" "$AUTH_LOGIN_PATH" "200|401|403" "$body" "" "json"
  file="$(last_file "auth admin signin")"
  ADMIN_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  ADMIN_USER_ID="$(json_get_any "$file" "data.user.id" "data.user.user_id" "user.id" "user.user_id" "sub")"
  [ "$ADMIN_USER_ID" = "" ] && ADMIN_USER_ID="$(jwt_claim "$ADMIN_TOKEN" "sub")"
  role="$(json_get_any "$file" "data.user.role" "user.role" "role")"
  admin_status="$(json_get_any "$file" "data.user.admin_status" "user.admin_status" "admin_status")"

  if [ "$ADMIN_TOKEN" = "" ]; then
    record_skip "admin token extracted" "admin signin failed or token unavailable"
    return 0
  fi

  record_pass "admin token extracted"
  if [ "$role" = "admin" ] && [ "$admin_status" = "approved" ]; then
    record_pass "admin token is approved admin"
  else
    record_skip "admin token is approved admin" "role=$role admin_status=$admin_status; cross-user admin checks may return 403"
  fi
}

system_endpoint_tests() {
  print_section "Public system API"
  user_request "user hello" "GET" "/hello" "200" "" "" "json"
  assert_json_status_ok "user hello"
  user_request "user health" "GET" "/health" "200|503" "" "" "json"
  assert_health_shape "user health"
  if [ "$(last_code "user health")" = "200" ]; then
    assert_json_status_ok "user health"
  else
    record_skip "user health fully up" "health returned 503; inspect dependency details"
  fi
  user_request "user docs" "GET" "/docs" "200" "" "" "html"

  if [ "$STRICT_PUBLIC_ROUTES" = "1" ]; then
    for path in "/" "/live" "/ready" "/healthy" "/openapi.json" "/v3/api-docs" "/swagger" "/swagger-ui" "/swagger-ui/index.html" "/documentation/json" "/redoc" "/actuator" "/actuator/health" "/metrics" "/debug"; do
      user_request "user rejected route $path" "GET" "$path" "404" "" "" "json"
    done
  fi
}

auth_contract_tests() {
  print_section "Authentication and authorization contract"
  user_request "me missing token" "GET" "/v1/users/me" "401" "" "" "json"
  assert_json_status_error "me missing token" "UNAUTHORIZED"
  user_request "me invalid token" "GET" "/v1/users/me" "401" "" "not-a-real-token" "json"
  assert_json_status_error "me invalid token" "UNAUTHORIZED"
  user_request "protected malformed bearer" "GET" "/v1/users/me" "401" "" "Bearer not-a-real-token" "json"
  user_request "wrong method hello" "POST" "/hello" "404|405" "{}" "" "json"
}

profile_preference_tests() {
  print_section "Profile, preferences, security, dashboard"
  user_request "current profile" "GET" "/v1/users/me" "200" "" "$ACCESS_TOKEN" "json"
  assert_json_status_ok "current profile"

  local profile_patch pref_body
  profile_patch=$(cat <<JSON
{
  "full_name": "User Service Full API Test User",
  "display_name": "UserFullSmoke",
  "bio": "Testing user_service APIs",
  "timezone": "Asia/Dhaka",
  "locale": "en",
  "metadata": {
    "run_id": "$RUN_ID"
  }
}
JSON
)
  user_request "update profile" "PATCH" "/v1/users/me" "200" "$profile_patch" "$ACCESS_TOKEN" "json"
  user_request "update profile malformed json" "PATCH" "/v1/users/me" "400" "{" "$ACCESS_TOKEN" "json"
  user_request "update profile unknown field" "PATCH" "/v1/users/me" "200|400" '{"unknown_field":"ignored-or-rejected"}' "$ACCESS_TOKEN" "json"

  user_request "preferences" "GET" "/v1/users/me/preferences" "200" "" "$ACCESS_TOKEN" "json"

  pref_body=$(cat <<JSON
{
  "timezone": "Asia/Dhaka",
  "locale": "en",
  "theme": "dark",
  "notifications_enabled": true,
  "dashboard_settings": {
    "density": "comfortable",
    "show_activity": true
  },
  "report_settings": {
    "default_format": "pdf"
  },
  "metadata": {
    "run_id": "$RUN_ID"
  }
}
JSON
)
  user_request "replace preferences" "PUT" "/v1/users/me/preferences" "200" "$pref_body" "$ACCESS_TOKEN" "json"
  user_request "replace preferences malformed json" "PUT" "/v1/users/me/preferences" "400" "{" "$ACCESS_TOKEN" "json"
  user_request "replace preferences invalid theme" "PUT" "/v1/users/me/preferences" "400|422" '{"timezone":"Asia/Dhaka","locale":"en","theme":"not-a-theme"}' "$ACCESS_TOKEN" "json"

  user_request "activity valid paging" "GET" "/v1/users/me/activity?limit=10&offset=0" "200" "" "$ACCESS_TOKEN" "json"
  user_request "dashboard" "GET" "/v1/users/me/dashboard" "200" "" "$ACCESS_TOKEN" "json"

  if [ "$EXPECT_EXTENDED_USER_ENDPOINTS" = "1" ]; then
    user_request "security context" "GET" "/v1/users/me/security-context" "200" "" "$ACCESS_TOKEN" "json"
    user_request "rbac view" "GET" "/v1/users/me/rbac" "200" "" "$ACCESS_TOKEN" "json"
    user_request "effective permissions" "GET" "/v1/users/me/effective-permissions" "200" "" "$ACCESS_TOKEN" "json"
  else
    user_request "security context optional" "GET" "/v1/users/me/security-context" "200|404" "" "$ACCESS_TOKEN" "json"
    user_request "rbac view optional" "GET" "/v1/users/me/rbac" "200|404" "" "$ACCESS_TOKEN" "json"
    user_request "effective permissions optional" "GET" "/v1/users/me/effective-permissions" "200|404" "" "$ACCESS_TOKEN" "json"
  fi
}

invalid_query_tests() {
  print_section "Invalid query-string coverage"
  user_request "activity invalid limit text" "GET" "/v1/users/me/activity?limit=abc" "400" "" "$ACCESS_TOKEN" "json"
  user_request "activity invalid limit zero" "GET" "/v1/users/me/activity?limit=0" "400" "" "$ACCESS_TOKEN" "json"
  user_request "activity invalid limit too large" "GET" "/v1/users/me/activity?limit=101" "400" "" "$ACCESS_TOKEN" "json"
  user_request "activity invalid offset text" "GET" "/v1/users/me/activity?offset=abc" "400" "" "$ACCESS_TOKEN" "json"
  user_request "activity invalid offset negative" "GET" "/v1/users/me/activity?offset=-1" "400" "" "$ACCESS_TOKEN" "json"
  user_request "reports invalid limit" "GET" "/v1/users/me/reports?limit=abc" "400" "" "$ACCESS_TOKEN" "json"
  user_request "access requests invalid offset" "GET" "/v1/users/access-requests?offset=-1" "400" "" "$ACCESS_TOKEN" "json"
}

seed_calculator_data() {
  if [ "$SEED_CALCULATOR" != "1" ] || [ "$CALCULATOR_BASE_URL" = "" ]; then
    record_skip "calculator seed" "CALCULATOR_BASE_URL missing or disabled"
    return 0
  fi

  print_section "Optional calculator seed for user projections"
  calc_request "calculator hello" "GET" "/hello" "200" "" "" "json"
  calc_request "calculator seed add" "POST" "/v1/calculator/calculate" "200" '{"operation":"ADD","operands":[10,20,5]}' "$ACCESS_TOKEN" "json"
  local file
  file="$(last_file "calculator seed add")"
  CALCULATION_ID="$(json_get_any "$file" "data.calculation_id" "data.id" "data.record.id" "data.record.calculation_id" "calculation_id" "id")"
  [ "$CALCULATION_ID" != "" ] && record_pass "calculation id extracted: $CALCULATION_ID" || record_skip "calculation id extracted" "calculator response did not expose id"

  calc_request "calculator seed expression" "POST" "/v1/calculator/calculate" "200" '{"expression":"sqrt(16)+(10+5)*3"}' "$ACCESS_TOKEN" "json"
}

seed_todo_data() {
  if [ "$SEED_TODO" != "1" ] || [ "$TODO_BASE_URL" = "" ]; then
    record_skip "todo seed" "TODO_BASE_URL missing or disabled"
    return 0
  fi

  print_section "Optional todo seed for user projections"
  local due body file
  due="$(iso_utc_hours 48)"
  todo_request "todo hello" "GET" "/hello" "200" "" "" "json"
  body=$(cat <<JSON
{
  "title": "User service full API seed todo $RUN_ID",
  "description": "Seed todo for user_service projection tests",
  "priority": "HIGH",
  "due_date": "$due",
  "tags": ["user-service", "smoke", "$RUN_ID"]
}
JSON
)
  todo_request "todo seed create" "POST" "/v1/todos" "200|201" "$body" "$ACCESS_TOKEN" "json"
  file="$(last_file "todo seed create")"
  TODO_ID="$(json_get_any "$file" "data.id" "data.todo.id" "data.todo.todo_id" "data.todo_id" "id" "todo_id")"
  if [ "$TODO_ID" != "" ]; then
    record_pass "todo id extracted: $TODO_ID"
    todo_request "todo seed complete" "POST" "/v1/todos/$TODO_ID/complete" "200|404|409" "" "$ACCESS_TOKEN" "json"
  else
    record_skip "todo id extracted" "todo response did not expose id"
  fi
}

projection_tests() {
  print_section "Projection reads"
  user_request "own calculations list" "GET" "/v1/users/me/calculations?limit=20&offset=0" "200" "" "$ACCESS_TOKEN" "json"
  if [ "$CALCULATION_ID" != "" ]; then
    user_request "own calculation detail seeded" "GET" "/v1/users/me/calculations/$CALCULATION_ID" "200|404" "" "$ACCESS_TOKEN" "json"
  else
    user_request "own missing calculation detail" "GET" "/v1/users/me/calculations/missing-calculation-id" "404" "" "$ACCESS_TOKEN" "json"
  fi

  user_request "own todos list" "GET" "/v1/users/me/todos?limit=20&offset=0" "200" "" "$ACCESS_TOKEN" "json"
  user_request "own todos summary" "GET" "/v1/users/me/todos/summary" "200" "" "$ACCESS_TOKEN" "json"
  user_request "own todos activity" "GET" "/v1/users/me/todos/activity?limit=20&offset=0" "200" "" "$ACCESS_TOKEN" "json"
  if [ "$TODO_ID" != "" ]; then
    user_request "own todo detail seeded" "GET" "/v1/users/me/todos/$TODO_ID" "200|404" "" "$ACCESS_TOKEN" "json"
  else
    user_request "own missing todo detail" "GET" "/v1/users/me/todos/missing-todo-id" "404" "" "$ACCESS_TOKEN" "json"
  fi

  user_request "report types" "GET" "/v1/users/reports/types" "200" "" "$ACCESS_TOKEN" "json"
}

cross_user_tests() {
  if [ "$SECOND_TOKEN" = "" ] || [ "$SECOND_USER_ID" = "" ]; then
    record_skip "cross-user forbidden checks" "second token/user id unavailable"
    return 0
  fi

  print_section "Cross-user forbidden checks without grant"
  user_request "second user forbidden primary calculations" "GET" "/v1/users/$USER_ID/calculations?limit=10" "403" "" "$SECOND_TOKEN" "json"
  assert_json_status_error "second user forbidden primary calculations" "FORBIDDEN"
  user_request "second user forbidden primary calculation detail" "GET" "/v1/users/$USER_ID/calculations/missing-calculation-id" "403|404" "" "$SECOND_TOKEN" "json"
  user_request "second user forbidden primary todos" "GET" "/v1/users/$USER_ID/todos?limit=10" "403" "" "$SECOND_TOKEN" "json"
  assert_json_status_error "second user forbidden primary todos" "FORBIDDEN"
  user_request "second user forbidden primary todos summary" "GET" "/v1/users/$USER_ID/todos/summary" "403" "" "$SECOND_TOKEN" "json"
  user_request "second user forbidden primary todos activity" "GET" "/v1/users/$USER_ID/todos/activity" "403" "" "$SECOND_TOKEN" "json"
  user_request "second user forbidden primary reports" "GET" "/v1/users/$USER_ID/reports?limit=10" "403" "" "$SECOND_TOKEN" "json"
  assert_json_status_error "second user forbidden primary reports" "FORBIDDEN"

  if [ "$ADMIN_TOKEN" != "" ]; then
    user_request "admin can read primary calculations" "GET" "/v1/users/$USER_ID/calculations?limit=10" "200|403" "" "$ADMIN_TOKEN" "json"
    user_request "admin can read primary todos" "GET" "/v1/users/$USER_ID/todos?limit=10" "200|403" "" "$ADMIN_TOKEN" "json"
    user_request "admin can read primary reports" "GET" "/v1/users/$USER_ID/reports?limit=10" "200|403" "" "$ADMIN_TOKEN" "json"
  fi
}

access_request_tests() {
  print_section "Access request flow and validation"
  user_request "access request missing body" "POST" "/v1/users/access-requests" "400" "{}" "$ACCESS_TOKEN" "json"

  local too_long access_too_long target_id access_expires access_body file
  too_long="2035-01-01T00:00:00Z"
  target_id="${SECOND_USER_ID:-target-$RUN_ID}"
  access_too_long=$(cat <<JSON
{
  "target_user_id": "$target_id",
  "resource_type": "calculator",
  "scope": "calculator:history:read",
  "reason": "ttl validation",
  "expires_at": "$too_long"
}
JSON
)
  user_request "access request ttl exceeded" "POST" "/v1/users/access-requests" "400" "$access_too_long" "$ACCESS_TOKEN" "json"

  access_expires="$(future_rfc3339_days "$ACCESS_REQUEST_TTL_DAYS")"
  access_body=$(cat <<JSON
{
  "target_user_id": "$target_id",
  "resource_type": "calculator",
  "scope": "calculator:history:read",
  "reason": "Need to test access request lifecycle.",
  "expires_at": "$access_expires"
}
JSON
)
  user_request "create access request" "POST" "/v1/users/access-requests" "200|201|409" "$access_body" "$ACCESS_TOKEN" "json"
  file="$(last_file "create access request")"
  ACCESS_REQUEST_ID="$(json_get_any "$file" "data.request_id" "data.id" "data.access_request.id" "request_id")"

  if [ "$ACCESS_REQUEST_ID" = "" ]; then
    record_skip "access request id extracted" "create response did not expose request id; body=$(short_body "$file" | tr '\n' ' ' | cut -c1-900)"
  else
    record_pass "access request id extracted: $ACCESS_REQUEST_ID"
    user_request "list access requests" "GET" "/v1/users/access-requests?limit=20&offset=0" "200" "" "$ACCESS_TOKEN" "json"
    user_request "get access request" "GET" "/v1/users/access-requests/$ACCESS_REQUEST_ID" "200" "" "$ACCESS_TOKEN" "json"
    user_request "cancel access request" "POST" "/v1/users/access-requests/$ACCESS_REQUEST_ID/cancel" "200|409" "" "$ACCESS_TOKEN" "json"
    user_request "cancel access request conflict" "POST" "/v1/users/access-requests/$ACCESS_REQUEST_ID/cancel" "409|404" "" "$ACCESS_TOKEN" "json"
  fi

  user_request "unknown access request" "GET" "/v1/users/access-requests/missing-request-id" "404" "" "$ACCESS_TOKEN" "json"
  user_request "cancel unknown access request" "POST" "/v1/users/access-requests/missing-request-id/cancel" "404" "" "$ACCESS_TOKEN" "json"
  user_request "list access grants" "GET" "/v1/users/access-grants?limit=20&offset=0" "200" "" "$ACCESS_TOKEN" "json"
}

report_request_tests() {
  print_section "User report request flow and validation"
  user_request "report missing body" "POST" "/v1/users/me/reports" "400" "{}" "$ACCESS_TOKEN" "json"

  local report_bad_format report_bad_dates report_body file
  report_bad_format=$(cat <<JSON
{
  "report_type": "calculator_history_report",
  "format": "docx",
  "date_from": "2026-05-01",
  "date_to": "2026-05-09",
  "filters": {},
  "options": {}
}
JSON
)
  user_request "report unsupported format" "POST" "/v1/users/me/reports" "400" "$report_bad_format" "$ACCESS_TOKEN" "json"

  report_bad_dates=$(cat <<JSON
{
  "report_type": "calculator_history_report",
  "format": "pdf",
  "date_from": "2026-05-10",
  "date_to": "2026-05-01",
  "filters": {},
  "options": {}
}
JSON
)
  user_request "report bad date order" "POST" "/v1/users/me/reports" "400" "$report_bad_dates" "$ACCESS_TOKEN" "json"

  report_body=$(cat <<JSON
{
  "report_type": "calculator_history_report",
  "format": "pdf",
  "date_from": "2026-05-01",
  "date_to": "2026-05-09",
  "filters": {
    "source": "smoke"
  },
  "options": {
    "run_id": "$RUN_ID"
  }
}
JSON
)
  user_request "create own report" "POST" "/v1/users/me/reports" "200|201" "$report_body" "$ACCESS_TOKEN" "json"
  file="$(last_file "create own report")"
  REPORT_ID="$(json_get_any "$file" "data.report_id" "data.id" "data.report.id" "report_id")"

  if [ "$REPORT_ID" = "" ]; then
    record_skip "report id extracted" "No report_id in create response; body=$(short_body "$file" | tr '\n' ' ' | cut -c1-900)"
  else
    record_pass "report id extracted: $REPORT_ID"
    user_request "list own reports" "GET" "/v1/users/me/reports?limit=20&offset=0" "200" "" "$ACCESS_TOKEN" "json"
    user_request "get own report" "GET" "/v1/users/me/reports/$REPORT_ID" "200" "" "$ACCESS_TOKEN" "json"
    user_request "own report metadata" "GET" "/v1/users/me/reports/$REPORT_ID/metadata" "200|404|409" "" "$ACCESS_TOKEN" "json"
    user_request "own report progress" "GET" "/v1/users/me/reports/$REPORT_ID/progress" "200|404" "" "$ACCESS_TOKEN" "json"
    user_request "cancel own report" "POST" "/v1/users/me/reports/$REPORT_ID/cancel" "200|409" "" "$ACCESS_TOKEN" "json"
    user_request "cancel own report conflict" "POST" "/v1/users/me/reports/$REPORT_ID/cancel" "409|404" "" "$ACCESS_TOKEN" "json"
  fi

  user_request "list own reports after create" "GET" "/v1/users/me/reports?limit=20&offset=0" "200" "" "$ACCESS_TOKEN" "json"
  user_request "unknown report" "GET" "/v1/users/me/reports/missing-report-id" "404" "" "$ACCESS_TOKEN" "json"
  user_request "cancel unknown report" "POST" "/v1/users/me/reports/missing-report-id/cancel" "404" "" "$ACCESS_TOKEN" "json"

  if [ "$SECOND_TOKEN" != "" ] && [ "$SECOND_USER_ID" != "" ]; then
    user_request "second user cannot list primary reports" "GET" "/v1/users/$USER_ID/reports?limit=10" "403" "" "$SECOND_TOKEN" "json"
  fi

  if [ "$ADMIN_TOKEN" != "" ] && [ "$SECOND_USER_ID" != "" ]; then
    user_request "admin request report for target user" "POST" "/v1/users/$SECOND_USER_ID/reports" "200|201|403|404" "$report_body" "$ADMIN_TOKEN" "json"
    user_request "admin list target user reports" "GET" "/v1/users/$SECOND_USER_ID/reports?limit=10" "200|403|404" "" "$ADMIN_TOKEN" "json"
  fi
}

downstream_report_seed_tests() {
  if [ "$SEED_REPORT" != "1" ] || [ "$REPORT_BASE_URL" = "" ]; then
    record_skip "report service seed" "REPORT_BASE_URL missing or disabled"
    return 0
  fi

  print_section "Optional report service compatibility checks"
  local body file
  report_request "report service hello" "GET" "/hello" "200" "" "" "json"
  report_request "report service list types" "GET" "/v1/reports/types" "200" "" "$ACCESS_TOKEN" "json"

  body=$(cat <<JSON
{
  "report_type": "calculator_history_report",
  "format": "json",
  "date_from": "2026-05-01",
  "date_to": "2026-05-09",
  "filters": {},
  "options": {
    "run_id": "$RUN_ID"
  }
}
JSON
)
  report_request "report service create report" "POST" "/v1/reports" "200|201" "$body" "$ACCESS_TOKEN" "json"
  file="$(last_file "report service create report")"
  REPORT_SERVICE_REPORT_ID="$(json_get_any "$file" "data.report_id" "data.report.report_id" "data.id" "report_id")"
  [ "$REPORT_SERVICE_REPORT_ID" != "" ] && record_pass "report service report id extracted: $REPORT_SERVICE_REPORT_ID" || record_skip "report service report id extracted" "response did not expose id"

  user_request "user own reports after report service create" "GET" "/v1/users/me/reports?limit=20&offset=0" "200" "" "$ACCESS_TOKEN" "json"
}

admin_compatibility_tests() {
  if [ "$ADMIN_BASE_URL" = "" ] || [ "$ADMIN_TOKEN" = "" ]; then
    record_skip "admin compatibility checks" "ADMIN_BASE_URL or admin token unavailable"
    return 0
  fi

  print_section "Optional admin service compatibility checks"
  admin_request "admin hello" "GET" "/hello" "200" "" "" "json"
  admin_request "admin user projection" "GET" "/v1/admin/users/$USER_ID" "200|403|404" "" "$ADMIN_TOKEN" "json"
  admin_request "admin user activity" "GET" "/v1/admin/users/$USER_ID/activity" "200|403|404" "" "$ADMIN_TOKEN" "json"
  admin_request "admin user reports" "GET" "/v1/admin/users/$USER_ID/reports" "200|403|404" "" "$ADMIN_TOKEN" "json"
  admin_request "admin user calculations" "GET" "/v1/admin/calculations/users/$USER_ID" "200|403|404" "" "$ADMIN_TOKEN" "json"
  admin_request "admin user todos" "GET" "/v1/admin/todos/users/$USER_ID" "200|403|404" "" "$ADMIN_TOKEN" "json"
}

final_negative_tests() {
  print_section "Wrong method and unknown path tests"
  user_request "wrong method protected" "DELETE" "/v1/users/me" "404|405" "" "$ACCESS_TOKEN" "json"
  user_request "unknown protected path" "GET" "/v1/users/not-a-real-path" "404" "" "$ACCESS_TOKEN" "json"
  user_request "malformed protected path" "GET" "/v1/users/%7Bbad%7D/calculations" "400|403|404" "" "$ACCESS_TOKEN" "json"
}

verify_response_code_coverage() {
  print_section "Response-code coverage"
  local required="200 400 401 403 404" missing="" code
  for code in $required; do
    case " $OBSERVED_CODES " in
      *" $code "*) record_pass "observed HTTP $code" ;;
      *) missing="$missing $code"; record_fail "observed HTTP $code" "not observed in this run" ;;
    esac
  done
  case " $OBSERVED_CODES " in
    *" 201 "*) record_pass "observed HTTP 201" ;;
    *) record_skip "observed HTTP 201" "implementation may return 200 for create" ;;
  esac
  case " $OBSERVED_CODES " in
    *" 405 "*) record_pass "observed HTTP 405" ;;
    *) record_skip "observed HTTP 405" "framework may return 404 for wrong method" ;;
  esac

  if [ "$missing" != "" ] && [ "$REQUIRED_CODE_COVERAGE" != "1" ]; then
    record_skip "strict response-code coverage" "missing:$missing, USER_TEST_REQUIRED_CODE_COVERAGE=$REQUIRED_CODE_COVERAGE"
  fi
}

print_header() {
  echo "${BOLD}${BLUE}User Service Full API Smoke Test${RESET}"
  echo "User Base URL:       $USER_BASE_URL"
  echo "Auth Base URL:       ${AUTH_BASE_URL:-<not provided>}"
  echo "Calculator Base URL: ${CALCULATOR_BASE_URL:-<not provided>}"
  echo "Todo Base URL:       ${TODO_BASE_URL:-<not provided>}"
  echo "Admin Base URL:      ${ADMIN_BASE_URL:-<not provided>}"
  echo "Report Base URL:     ${REPORT_BASE_URL:-<not provided>}"
  echo "Run ID:              $RUN_ID"
  echo "Timeout seconds:     $TIMEOUT"
  echo "Retries/request:     $REQUEST_RETRIES"
  echo
}

print_header

if [ "$AUTH_BASE_URL" != "" ]; then
  auth_request "auth hello" "GET" "/hello" "200" "" "" "json"
  auth_request "auth health" "GET" "/health" "200|503" "" "" "json"
fi

login_primary_user
login_second_user
login_admin_token

if [ "$ACCESS_TOKEN" = "" ] || [ "$USER_ID" = "" ]; then
  echo
  echo "Cannot continue protected user-service tests without primary access token and user id."
  exit 1
fi

system_endpoint_tests
auth_contract_tests
profile_preference_tests
invalid_query_tests
seed_calculator_data
seed_todo_data
projection_tests
cross_user_tests
access_request_tests
report_request_tests
downstream_report_seed_tests
admin_compatibility_tests
final_negative_tests
verify_response_code_coverage

user_request "user health after api checks" "GET" "/health" "200|503" "" "" "json"
assert_health_shape "user health after api checks"

echo
printf "%sSummary:%s %s total, %s passed, %s failed, %s skipped\n" "$BOLD" "$RESET" "$TEST_COUNT" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
echo "User Base URL:        $USER_BASE_URL"
echo "Auth Base URL:        ${AUTH_BASE_URL:-<not provided>}"
echo "Calculator Base URL:  ${CALCULATOR_BASE_URL:-<not provided>}"
echo "Todo Base URL:        ${TODO_BASE_URL:-<not provided>}"
echo "Admin Base URL:       ${ADMIN_BASE_URL:-<not provided>}"
echo "Report Base URL:      ${REPORT_BASE_URL:-<not provided>}"
echo "Primary username:     $TEST_USERNAME"
echo "Primary user id:      $USER_ID"
echo "Second user id:       $SECOND_USER_ID"
echo "Admin user id:        $ADMIN_USER_ID"
echo "Calculation id:       $CALCULATION_ID"
echo "Todo id:              $TODO_ID"
echo "User report id:       $REPORT_ID"
echo "Report svc report id: $REPORT_SERVICE_REPORT_ID"
echo "Access request id:    $ACCESS_REQUEST_ID"
echo "Observed HTTP codes:  $OBSERVED_CODES"
if [ "$SAVE_RESPONSES" = "1" ]; then echo "Response files:       $TMP_DIR"; fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo
  echo "One or more user service checks failed. Review the failure messages above."
  exit 1
fi

echo
printf "%sAll required user service checks passed.%s\n" "$GREEN" "$RESET"
exit 0
