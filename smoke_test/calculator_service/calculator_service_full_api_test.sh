#!/usr/bin/env bash
# Calculator Service full API + cross-service integration test script.
#
# Usage:
#   chmod +x calculator_service_full_api_test.sh
#   cp calculator_service_full_api_test.env.example calculator_service_full_api_test.env
#   ./calculator_service_full_api_test.sh ./calculator_service_full_api_test.env
#
# This script uses auth_service to create/sign in users and obtain JWTs, then tests
# calculator_service public/protected/business APIs. Optional integration checks
# read calculator projections through admin_service, user_service, and report_service.

set -u

ENV_FILE="${1:-./calculator_service_full_api_test.env}"
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing env file: $ENV_FILE"
  echo "Create one from calculator_service_full_api_test.env.example"
  exit 2
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

CALCULATOR_BASE_URL="${CALCULATOR_BASE_URL%/}"
AUTH_BASE_URL="${AUTH_BASE_URL%/}"
ADMIN_BASE_URL="${ADMIN_BASE_URL:-}"
USER_BASE_URL="${USER_BASE_URL:-}"
REPORT_BASE_URL="${REPORT_BASE_URL:-}"
ADMIN_BASE_URL="${ADMIN_BASE_URL%/}"
USER_BASE_URL="${USER_BASE_URL%/}"
REPORT_BASE_URL="${REPORT_BASE_URL%/}"

TIMEOUT="${CALCULATOR_TEST_TIMEOUT:-25}"
VERBOSE="${CALCULATOR_TEST_VERBOSE:-0}"
TENANT="${CALCULATOR_TEST_TENANT:-dev}"
EVENT_SETTLE_SECONDS="${CALCULATOR_TEST_EVENT_SETTLE_SECONDS:-3}"
ENABLE_ADMIN_CHECKS="${CALCULATOR_TEST_ENABLE_ADMIN_CHECKS:-1}"
ENABLE_USER_CHECKS="${CALCULATOR_TEST_ENABLE_USER_CHECKS:-1}"
ENABLE_REPORT_CHECKS="${CALCULATOR_TEST_ENABLE_REPORT_CHECKS:-1}"
ENABLE_DELETE_HISTORY="${CALCULATOR_TEST_ENABLE_DELETE_HISTORY:-1}"

ADMIN_USERNAME="${AUTH_TEST_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${AUTH_TEST_ADMIN_PASSWORD:-admin123}"
USER_PASSWORD="${AUTH_TEST_USER_PASSWORD:-Test1234!Aa}"
SECOND_USER_PASSWORD="${AUTH_TEST_SECOND_USER_PASSWORD:-Other1234!Aa}"

RUN_ID="$(date +%s)-$RANDOM"
OWNER_USERNAME="calc_owner_${RUN_ID}"
OWNER_EMAIL="${OWNER_USERNAME}@example.com"
OTHER_USERNAME="calc_other_${RUN_ID}"
OTHER_EMAIL="${OTHER_USERNAME}@example.com"

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

json_find_first() {
  # json_find_first <file> <key1,key2,key3>
  python3 - "$1" "$2" <<'PY'
import json, sys
file_path = sys.argv[1]
keys = [k.strip() for k in sys.argv[2].split(',') if k.strip()]
try:
    obj = json.load(open(file_path, encoding='utf-8'))
except Exception:
    print('')
    sys.exit(0)

def walk(x):
    if isinstance(x, dict):
        for key in keys:
            if key in x and x[key] not in (None, ''):
                return x[key]
        for v in x.values():
            found = walk(v)
            if found not in (None, ''):
                return found
    elif isinstance(x, list):
        for v in x:
            found = walk(v)
            if found not in (None, ''):
                return found
    return None

found = walk(obj)
if isinstance(found, (dict, list)):
    print(json.dumps(found, separators=(',', ':')))
elif found is None:
    print('')
else:
    print(found)
PY
}

jwt_get() {
  # jwt_get <jwt> <claim>
  python3 - "$1" "$2" <<'PY'
import base64, json, sys
jwt, claim = sys.argv[1], sys.argv[2]
try:
    payload = jwt.split('.')[1]
    payload += '=' * (-len(payload) % 4)
    obj = json.loads(base64.urlsafe_b64decode(payload.encode()))
    val = obj.get(claim)
    if isinstance(val, (dict, list)):
        print(json.dumps(val, separators=(',', ':')))
    elif val is None:
        print('')
    else:
        print(val)
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
        def redact(x):
            if isinstance(x, dict):
                out = {}
                for k, v in x.items():
                    if k.lower() in {'access_token','refresh_token','authorization','password','new_password','current_password','token'}:
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

sanitize_name() {
  printf '%s' "$1" | sed 's/[^A-Za-z0-9_]/_/g'
}

request_to() {
  # request_to <service_label> <base_url> <forwarded_proto> <name> <method> <path> <expected_codes_regex> <body_or_empty> <bearer_token_or_empty>
  local service="$1"
  local base_url="$2"
  local forwarded_proto="$3"
  local name="$4"
  local method="$5"
  local path="$6"
  local expected="$7"
  local body="${8:-}"
  local token="${9:-}"
  local safe_name
  safe_name="$(sanitize_name "${service}_${name}")"
  local outfile="$TMP_DIR/${safe_name}.json"
  local req_id="req-$(new_uuid)"
  local trace_id
  trace_id="$(new_uuid | tr -d '-')"
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

  echo "$outfile" > "$TMP_DIR/${safe_name}.path"
  echo "$http_code" > "$TMP_DIR/${safe_name}.code"

  if [ "$VERBOSE" = "1" ]; then
    echo "--- [$service] $name response ($http_code) ---"
    short_body "$outfile"
    echo "----------------------------------------------"
  fi

  if [ "$curl_exit" -ne 0 ]; then
    record_fail "[$service] $name" "curl failed: $(cat "$outfile.curlerr")"
    return 1
  fi

  if printf '%s' "$http_code" | grep -Eq "^($expected)$"; then
    record_pass "[$service] $name ($method $path -> HTTP $http_code)"
    return 0
  fi

  record_fail "[$service] $name ($method $path expected HTTP $expected but got $http_code)" "response: $(short_body "$outfile" | tr '\n' ' ' | cut -c1-1100)"
  return 1
}

calc_request() {
  request_to "calculator" "$CALCULATOR_BASE_URL" "${CALCULATOR_FORWARDED_PROTO:-}" "$@"
}

auth_request() {
  request_to "auth" "$AUTH_BASE_URL" "${AUTH_FORWARDED_PROTO:-}" "$@"
}

admin_request() {
  request_to "admin" "$ADMIN_BASE_URL" "${ADMIN_FORWARDED_PROTO:-}" "$@"
}

user_request() {
  request_to "user" "$USER_BASE_URL" "${USER_FORWARDED_PROTO:-}" "$@"
}

report_request() {
  request_to "report" "$REPORT_BASE_URL" "${REPORT_FORWARDED_PROTO:-}" "$@"
}

last_file() {
  cat "$TMP_DIR/$(sanitize_name "$1_$2").path" 2>/dev/null || true
}

print_header() {
  echo "${BOLD}${BLUE}Calculator Service Full API Test${RESET}"
  echo "Calculator Base URL: $CALCULATOR_BASE_URL"
  echo "Auth Base URL:       $AUTH_BASE_URL"
  echo "Admin Base URL:      ${ADMIN_BASE_URL:-<disabled>}"
  echo "User Base URL:       ${USER_BASE_URL:-<disabled>}"
  echo "Report Base URL:     ${REPORT_BASE_URL:-<disabled>}"
  echo "Tenant:              $TENANT"
  echo "Timeout:             ${TIMEOUT}s"
  echo "Run ID:              $RUN_ID"
  echo
}

extract_token_pair() {
  # extract_token_pair <file> prints access\nrefresh
  local f="$1"
  local access refresh
  access="$(json_get "$f" "data.tokens.access_token")"
  refresh="$(json_get "$f" "data.tokens.refresh_token")"
  if [ "$access" = "" ]; then access="$(json_find_first "$f" "access_token,accessToken")"; fi
  if [ "$refresh" = "" ]; then refresh="$(json_find_first "$f" "refresh_token,refreshToken")"; fi
  printf '%s\n%s\n' "$access" "$refresh"
}

print_header

# -----------------------------------------------------------------------------
# Public calculator routes
# -----------------------------------------------------------------------------
calc_request "hello" "GET" "/hello" "200" "" ""
HELLO_FILE="$(last_file calculator hello)"
if [ -n "$HELLO_FILE" ] && [ "$(json_status "$HELLO_FILE")" = "ok" ]; then
  record_pass "[calculator] hello envelope status is ok"
else
  record_fail "[calculator] hello envelope status is ok" "expected JSON status=ok"
fi

calc_request "health" "GET" "/health" "200|503" "" ""
HEALTH_FILE="$(last_file calculator health)"
if [ -n "$HEALTH_FILE" ]; then
  HEALTH_STATUS="$(json_status "$HEALTH_FILE")"
  if [ "$HEALTH_STATUS" = "ok" ]; then
    record_pass "[calculator] health envelope status is ok"
  else
    record_fail "[calculator] health envelope status is ok" "health status=$HEALTH_STATUS response=$(short_body "$HEALTH_FILE" | tr '\n' ' ' | cut -c1-900)"
  fi
fi

calc_request "docs" "GET" "/docs" "200" "" ""
calc_request "root rejected" "GET" "/" "404" "" ""
calc_request "live rejected" "GET" "/live" "404" "" ""
calc_request "ready rejected" "GET" "/ready" "404" "" ""
calc_request "healthy rejected" "GET" "/healthy" "404" "" ""
calc_request "openapi json rejected" "GET" "/openapi.json" "404|401|403" "" ""

# -----------------------------------------------------------------------------
# Auth setup
# -----------------------------------------------------------------------------
OWNER_SIGNUP_BODY=$(cat <<JSON
{
  "username": "$OWNER_USERNAME",
  "email": "$OWNER_EMAIL",
  "password": "$USER_PASSWORD",
  "full_name": "Calculator Test Owner",
  "birthdate": "1998-05-20",
  "gender": "male",
  "account_type": "user"
}
JSON
)
auth_request "signup owner user" "POST" "/v1/signup" "200|201|409" "$OWNER_SIGNUP_BODY" ""
OWNER_SIGNUP_FILE="$(last_file auth "signup owner user")"

OWNER_SIGNIN_BODY=$(cat <<JSON
{
  "username_or_email": "$OWNER_USERNAME",
  "password": "$USER_PASSWORD",
  "device_id": "calculator-full-api-test"
}
JSON
)
auth_request "signin owner user" "POST" "/v1/signin" "200" "$OWNER_SIGNIN_BODY" ""
OWNER_SIGNIN_FILE="$(last_file auth "signin owner user")"
OWNER_ACCESS_TOKEN="$(extract_token_pair "$OWNER_SIGNIN_FILE" | sed -n '1p')"
OWNER_REFRESH_TOKEN="$(extract_token_pair "$OWNER_SIGNIN_FILE" | sed -n '2p')"
OWNER_USER_ID="$(json_get "$OWNER_SIGNIN_FILE" "data.user.id")"
if [ "$OWNER_USER_ID" = "" ]; then OWNER_USER_ID="$(jwt_get "$OWNER_ACCESS_TOKEN" "sub")"; fi

OTHER_SIGNUP_BODY=$(cat <<JSON
{
  "username": "$OTHER_USERNAME",
  "email": "$OTHER_EMAIL",
  "password": "$SECOND_USER_PASSWORD",
  "full_name": "Calculator Test Other User",
  "birthdate": "1998-05-20",
  "gender": "female",
  "account_type": "user"
}
JSON
)
auth_request "signup other user" "POST" "/v1/signup" "200|201|409" "$OTHER_SIGNUP_BODY" ""
OTHER_SIGNIN_BODY=$(cat <<JSON
{
  "username_or_email": "$OTHER_USERNAME",
  "password": "$SECOND_USER_PASSWORD",
  "device_id": "calculator-full-api-test-other"
}
JSON
)
auth_request "signin other user" "POST" "/v1/signin" "200" "$OTHER_SIGNIN_BODY" ""
OTHER_SIGNIN_FILE="$(last_file auth "signin other user")"
OTHER_ACCESS_TOKEN="$(extract_token_pair "$OTHER_SIGNIN_FILE" | sed -n '1p')"
OTHER_USER_ID="$(json_get "$OTHER_SIGNIN_FILE" "data.user.id")"
if [ "$OTHER_USER_ID" = "" ]; then OTHER_USER_ID="$(jwt_get "$OTHER_ACCESS_TOKEN" "sub")"; fi

ADMIN_SIGNIN_BODY=$(cat <<JSON
{
  "username_or_email": "$ADMIN_USERNAME",
  "password": "$ADMIN_PASSWORD",
  "device_id": "calculator-full-api-test-admin"
}
JSON
)
auth_request "signin bootstrap admin" "POST" "/v1/signin" "200|401" "$ADMIN_SIGNIN_BODY" ""
ADMIN_SIGNIN_FILE="$(last_file auth "signin bootstrap admin")"
ADMIN_ACCESS_TOKEN="$(extract_token_pair "$ADMIN_SIGNIN_FILE" | sed -n '1p')"
ADMIN_ROLE="$(json_get "$ADMIN_SIGNIN_FILE" "data.user.role")"
ADMIN_STATUS="$(json_get "$ADMIN_SIGNIN_FILE" "data.user.admin_status")"

if [ "$OWNER_ACCESS_TOKEN" = "" ] || [ "$OWNER_USER_ID" = "" ]; then
  record_fail "auth setup owner token and user id" "owner token or user id missing; cannot continue protected calculator checks"
else
  record_pass "auth setup owner token and user id"
fi

if [ "$OTHER_ACCESS_TOKEN" = "" ] || [ "$OTHER_USER_ID" = "" ]; then
  record_fail "auth setup other token and user id" "other token or user id missing"
else
  record_pass "auth setup other token and user id"
fi

if [ "$ADMIN_ACCESS_TOKEN" != "" ] && [ "$ADMIN_ROLE" = "admin" ] && [ "$ADMIN_STATUS" = "approved" ]; then
  record_pass "auth setup approved admin token"
else
  record_skip "auth setup approved admin token" "default admin sign-in unavailable or not approved; admin authorization checks will be limited"
fi

if [ "$OWNER_ACCESS_TOKEN" != "" ]; then
  TOKEN_ISS="$(jwt_get "$OWNER_ACCESS_TOKEN" "iss")"
  TOKEN_AUD="$(jwt_get "$OWNER_ACCESS_TOKEN" "aud")"
  TOKEN_TENANT="$(jwt_get "$OWNER_ACCESS_TOKEN" "tenant")"
  TOKEN_ROLE="$(jwt_get "$OWNER_ACCESS_TOKEN" "role")"
  if [ "$TOKEN_ISS" = "auth" ] && [ "$TOKEN_AUD" = "micro-app" ] && [ "$TOKEN_ROLE" = "user" ]; then
    record_pass "owner JWT has expected iss/aud/role claims"
  else
    record_fail "owner JWT has expected iss/aud/role claims" "iss=$TOKEN_ISS aud=$TOKEN_AUD role=$TOKEN_ROLE tenant=$TOKEN_TENANT"
  fi
fi

# -----------------------------------------------------------------------------
# Protected calculator auth behavior
# -----------------------------------------------------------------------------
calc_request "operations without token" "GET" "/v1/calculator/operations" "401" "" ""
calc_request "operations invalid token" "GET" "/v1/calculator/operations" "401" "" "not.a.valid.jwt"

if [ "$OWNER_ACCESS_TOKEN" != "" ]; then
  calc_request "operations with valid token" "GET" "/v1/calculator/operations" "200" "" "$OWNER_ACCESS_TOKEN"
else
  record_skip "[calculator] operations with valid token" "owner token missing"
fi

# -----------------------------------------------------------------------------
# Valid calculation operations
# -----------------------------------------------------------------------------
CALCULATION_ID=""
if [ "$OWNER_ACCESS_TOKEN" != "" ]; then
  while IFS='|' read -r op operands; do
    [ "$op" = "" ] && continue
    BODY=$(cat <<JSON
{
  "operation": "$op",
  "operands": $operands
}
JSON
)
    calc_request "calculate operation $op" "POST" "/v1/calculator/calculate" "200|201" "$BODY" "$OWNER_ACCESS_TOKEN"
    OP_FILE="$(last_file calculator "calculate operation $op")"
    FOUND_ID="$(json_find_first "$OP_FILE" "calculation_id,calculationId,id,record_id,recordId")"
    if [ "$CALCULATION_ID" = "" ] && [ "$FOUND_ID" != "" ]; then
      CALCULATION_ID="$FOUND_ID"
    fi
  done <<'OPS'
ADD|[10,20]
SUBTRACT|[30,5]
MULTIPLY|[6,7]
DIVIDE|[20,4]
MODULO|[20,6]
POWER|[2,8]
SQRT|[16]
PERCENTAGE|[20,200]
SIN|[0]
COS|[0]
TAN|[0]
LOG|[100]
LN|[2.718281828]
ABS|[-9]
ROUND|[3.6]
FLOOR|[3.9]
CEIL|[3.1]
FACTORIAL|[5]
OPS

  EXPRESSION_BODY=$(cat <<'JSON'
{
  "expression": "sqrt(16)+(10+5)*3"
}
JSON
)
  calc_request "calculate valid expression" "POST" "/v1/calculator/calculate" "200|201" "$EXPRESSION_BODY" "$OWNER_ACCESS_TOKEN"
  EXPRESSION_FILE="$(last_file calculator "calculate valid expression")"
  FOUND_ID="$(json_find_first "$EXPRESSION_FILE" "calculation_id,calculationId,id,record_id,recordId")"
  if [ "$CALCULATION_ID" = "" ] && [ "$FOUND_ID" != "" ]; then
    CALCULATION_ID="$FOUND_ID"
  fi
else
  record_skip "[calculator] valid calculation operations" "owner token missing"
fi

if [ "$CALCULATION_ID" != "" ]; then
  record_pass "captured calculation id: $CALCULATION_ID"
else
  record_skip "captured calculation id" "calculator response did not expose an obvious calculation id; record-detail checks will be skipped"
fi

# -----------------------------------------------------------------------------
# Invalid calculation requests
# -----------------------------------------------------------------------------
if [ "$OWNER_ACCESS_TOKEN" != "" ]; then
  calc_request "calculate missing body" "POST" "/v1/calculator/calculate" "400|422" "{}" "$OWNER_ACCESS_TOKEN"
  calc_request "calculate unsupported operation" "POST" "/v1/calculator/calculate" "400|422" '{"operation":"UNKNOWN","operands":[1,2]}' "$OWNER_ACCESS_TOKEN"
  calc_request "calculate divide by zero" "POST" "/v1/calculator/calculate" "400|422" '{"operation":"DIVIDE","operands":[10,0]}' "$OWNER_ACCESS_TOKEN"
  calc_request "calculate invalid operand count" "POST" "/v1/calculator/calculate" "400|422" '{"operation":"ADD","operands":[1]}' "$OWNER_ACCESS_TOKEN"
  calc_request "calculate invalid expression" "POST" "/v1/calculator/calculate" "400|422" '{"expression":"sqrt("}' "$OWNER_ACCESS_TOKEN"
  LONG_EXPR="1"
  for _ in $(seq 1 600); do LONG_EXPR="${LONG_EXPR}+1"; done
  calc_request "calculate too long expression" "POST" "/v1/calculator/calculate" "400|413|422" "{\"expression\":\"$LONG_EXPR\"}" "$OWNER_ACCESS_TOKEN"
else
  record_skip "[calculator] invalid calculation requests" "owner token missing"
fi

# -----------------------------------------------------------------------------
# History and record APIs
# -----------------------------------------------------------------------------
if [ "$OWNER_ACCESS_TOKEN" != "" ]; then
  calc_request "own history" "GET" "/v1/calculator/history" "200" "" "$OWNER_ACCESS_TOKEN"
  calc_request "own history with limit" "GET" "/v1/calculator/history?limit=5" "200" "" "$OWNER_ACCESS_TOKEN"
  calc_request "own history by user id" "GET" "/v1/calculator/history/$OWNER_USER_ID" "200" "" "$OWNER_ACCESS_TOKEN"
fi

if [ "$CALCULATION_ID" != "" ] && [ "$OWNER_ACCESS_TOKEN" != "" ]; then
  calc_request "record detail own calculation" "GET" "/v1/calculator/records/$CALCULATION_ID" "200" "" "$OWNER_ACCESS_TOKEN"
else
  record_skip "[calculator] record detail own calculation" "calculation id or owner token missing"
fi

if [ "$OTHER_ACCESS_TOKEN" != "" ] && [ "$OWNER_USER_ID" != "" ]; then
  calc_request "cross user history without grant forbidden" "GET" "/v1/calculator/history/$OWNER_USER_ID" "403" "" "$OTHER_ACCESS_TOKEN"
else
  record_skip "[calculator] cross user history without grant forbidden" "other token or owner user id missing"
fi

if [ "$ADMIN_ACCESS_TOKEN" != "" ] && [ "$OWNER_USER_ID" != "" ]; then
  calc_request "admin cross user history allowed" "GET" "/v1/calculator/history/$OWNER_USER_ID" "200" "" "$ADMIN_ACCESS_TOKEN"
else
  record_skip "[calculator] admin cross user history allowed" "approved admin token or owner id missing"
fi

if [ "$OWNER_ACCESS_TOKEN" != "" ] && [ "$ENABLE_DELETE_HISTORY" = "1" ]; then
  calc_request "delete own history" "DELETE" "/v1/calculator/history" "200|204" "" "$OWNER_ACCESS_TOKEN"
  calc_request "own history after delete" "GET" "/v1/calculator/history" "200" "" "$OWNER_ACCESS_TOKEN"
else
  record_skip "[calculator] delete own history" "disabled or owner token missing"
fi

# -----------------------------------------------------------------------------
# Optional cross-service projection checks
# -----------------------------------------------------------------------------
if [ "$EVENT_SETTLE_SECONDS" != "0" ]; then
  echo
  echo "Waiting ${EVENT_SETTLE_SECONDS}s for Kafka projections..."
  sleep "$EVENT_SETTLE_SECONDS"
fi

if [ "$ENABLE_ADMIN_CHECKS" = "1" ] && [ "$ADMIN_BASE_URL" != "" ] && [ "$ADMIN_ACCESS_TOKEN" != "" ]; then
  admin_request "admin hello" "GET" "/hello" "200" "" ""
  admin_request "admin calculation summary" "GET" "/v1/admin/calculations/summary" "200" "" "$ADMIN_ACCESS_TOKEN"
  admin_request "admin calculations list" "GET" "/v1/admin/calculations" "200" "" "$ADMIN_ACCESS_TOKEN"
  if [ "$OWNER_USER_ID" != "" ]; then
    admin_request "admin user calculations" "GET" "/v1/admin/calculations/users/$OWNER_USER_ID" "200" "" "$ADMIN_ACCESS_TOKEN"
  fi
  if [ "$CALCULATION_ID" != "" ]; then
    admin_request "admin calculation detail projection" "GET" "/v1/admin/calculations/$CALCULATION_ID" "200|404" "" "$ADMIN_ACCESS_TOKEN"
  fi
elif [ "$ENABLE_ADMIN_CHECKS" = "1" ]; then
  record_skip "[admin] projection checks" "ADMIN_BASE_URL or ADMIN_ACCESS_TOKEN missing"
fi

if [ "$ENABLE_USER_CHECKS" = "1" ] && [ "$USER_BASE_URL" != "" ] && [ "$OWNER_ACCESS_TOKEN" != "" ]; then
  user_request "user hello" "GET" "/hello" "200" "" ""
  user_request "user own calculation projections" "GET" "/v1/users/me/calculations" "200" "" "$OWNER_ACCESS_TOKEN"
  if [ "$CALCULATION_ID" != "" ]; then
    user_request "user own calculation projection detail" "GET" "/v1/users/me/calculations/$CALCULATION_ID" "200|404" "" "$OWNER_ACCESS_TOKEN"
  fi
  if [ "$OTHER_ACCESS_TOKEN" != "" ] && [ "$OWNER_USER_ID" != "" ]; then
    user_request "user cross calculation without grant forbidden" "GET" "/v1/users/$OWNER_USER_ID/calculations" "403|404" "" "$OTHER_ACCESS_TOKEN"
  fi
elif [ "$ENABLE_USER_CHECKS" = "1" ]; then
  record_skip "[user] projection checks" "USER_BASE_URL or owner token missing"
fi

if [ "$ENABLE_REPORT_CHECKS" = "1" ] && [ "$REPORT_BASE_URL" != "" ] && [ "$OWNER_ACCESS_TOKEN" != "" ]; then
  REPORT_TYPE="${CALCULATOR_TEST_REPORT_TYPE:-calculator_history_report}"
  REPORT_FORMAT="${CALCULATOR_TEST_REPORT_FORMAT:-pdf}"
  DATE_FROM="$(date -u -d '7 days ago' +%F 2>/dev/null || date -u +%F)"
  DATE_TO="$(date -u +%F)"
  report_request "report hello" "GET" "/hello" "200" "" ""
  report_request "report types" "GET" "/v1/reports/types" "200" "" "$OWNER_ACCESS_TOKEN"
  REPORT_BODY=$(cat <<JSON
{
  "report_type": "$REPORT_TYPE",
  "format": "$REPORT_FORMAT",
  "date_from": "$DATE_FROM",
  "date_to": "$DATE_TO",
  "filters": {},
  "options": {}
}
JSON
)
  report_request "request calculator report" "POST" "/v1/reports" "200|201|202" "$REPORT_BODY" "$OWNER_ACCESS_TOKEN"
  REPORT_FILE="$(last_file report "request calculator report")"
  REPORT_ID="$(json_find_first "$REPORT_FILE" "report_id,reportId,id")"
  if [ "$REPORT_ID" != "" ]; then
    report_request "report status" "GET" "/v1/reports/$REPORT_ID" "200" "" "$OWNER_ACCESS_TOKEN"
    report_request "report metadata maybe pending" "GET" "/v1/reports/$REPORT_ID/metadata" "200|202|404|409" "" "$OWNER_ACCESS_TOKEN"
  else
    record_skip "[report] report status" "report id not returned"
  fi
elif [ "$ENABLE_REPORT_CHECKS" = "1" ]; then
  record_skip "[report] integration checks" "REPORT_BASE_URL or owner token missing"
fi

# -----------------------------------------------------------------------------
# Final health
# -----------------------------------------------------------------------------
calc_request "final health" "GET" "/health" "200|503" "" ""
FINAL_HEALTH_FILE="$(last_file calculator "final health")"
if [ -n "$FINAL_HEALTH_FILE" ] && [ "$(json_status "$FINAL_HEALTH_FILE")" = "ok" ]; then
  record_pass "[calculator] final health status is ok"
else
  record_fail "[calculator] final health status is ok" "response=$(short_body "$FINAL_HEALTH_FILE" | tr '\n' ' ' | cut -c1-900)"
fi

echo
printf "%sSummary:%s %s total, %s passed, %s failed, %s skipped\n" "$BOLD" "$RESET" "$TEST_COUNT" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
echo "Owner user:       $OWNER_USERNAME / $OWNER_EMAIL / id=$OWNER_USER_ID"
echo "Other user:       $OTHER_USERNAME / $OTHER_EMAIL / id=$OTHER_USER_ID"
echo "Calculation id:   ${CALCULATION_ID:-<not captured>}"
echo "Calculator URL:   $CALCULATOR_BASE_URL"
echo "Auth URL:         $AUTH_BASE_URL"

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo
  echo "One or more calculator service checks failed. Review the failure messages above."
  exit 1
fi

echo
printf "%sAll required calculator service checks passed.%s\n" "$GREEN" "$RESET"
exit 0
