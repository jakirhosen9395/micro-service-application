#!/usr/bin/env bash
# Calculator Service API smoke/contract test script.
#
# Usage:
#   chmod +x calculator_service_api_smoke_test.sh
#   ./calculator_service_api_smoke_test.sh <calculator-ip-or-url> <auth-ip-or-url>
#   ./calculator_service_api_smoke_test.sh <calculator-ip> <calculator-port> <auth-ip> <auth-port>
#
# Examples:
#   ./calculator_service_api_smoke_test.sh 192.168.56.100 2020 192.168.56.100 6060
#   ./calculator_service_api_smoke_test.sh http://192.168.56.100:2020 http://192.168.56.100:6060
#
# Optional environment variables:
#   CALC_TEST_TIMEOUT=20
#   CALC_TEST_VERBOSE=1
#   CALC_TEST_SAVE_RESPONSES=0
#
# Auth options:
#   CALC_TEST_AUTH_LOGIN_PATH=/v1/signin
#   CALC_TEST_CREATE_USER=1
#   CALC_TEST_USERNAME=<existing-user>
#   CALC_TEST_PASSWORD=<existing-password>
#   CALC_TEST_ADMIN_USERNAME=admin
#   CALC_TEST_ADMIN_PASSWORD=admin123
#   CALC_TEST_CREATE_SECOND_USER=1
#
# Mutation options:
#   CALC_TEST_DELETE_HISTORY=1
#     Safe by default when CALC_TEST_CREATE_USER=1 because it clears only the test user's calculator history.
#     Set CALC_TEST_DELETE_HISTORY=0 to skip DELETE /v1/calculator/history.
#
# What it verifies:
#   - public system endpoints
#   - rejected non-contract routes
#   - JWT 401/403 behavior
#   - Swagger docs availability
#   - all supported operation calculations
#   - expression mode calculations
#   - expected validation failures
#   - history, cross-user own-history route, record lookup, and soft clear
#   - optional approved-admin cross-user read
#   - optional normal-user forbidden cross-user read

set -u

usage() {
  cat <<'USAGE'
Usage:
  ./calculator_service_api_smoke_test.sh <calculator-ip-or-url> <auth-ip-or-url>
  ./calculator_service_api_smoke_test.sh <calculator-ip> <calculator-port> <auth-ip> <auth-port>

Examples:
  ./calculator_service_api_smoke_test.sh 192.168.56.100 2020 192.168.56.100 6060
  ./calculator_service_api_smoke_test.sh http://192.168.56.100:2020 http://192.168.56.100:6060

Optional environment variables:
  CALC_TEST_TIMEOUT=20
  CALC_TEST_VERBOSE=1
  CALC_TEST_SAVE_RESPONSES=0
  CALC_TEST_AUTH_LOGIN_PATH=/v1/signin
  CALC_TEST_CREATE_USER=1
  CALC_TEST_USERNAME=<existing-user>
  CALC_TEST_PASSWORD=<existing-password>
  CALC_TEST_ADMIN_USERNAME=admin
  CALC_TEST_ADMIN_PASSWORD=admin123
  CALC_TEST_CREATE_SECOND_USER=1
  CALC_TEST_DELETE_HISTORY=1
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
  CALC_BASE_URL="$(normalize_base_url "$1" 2020)"
  AUTH_BASE_URL="$(normalize_base_url "$2" 6060)"
elif [ "$#" -ge 4 ]; then
  CALC_BASE_URL="$(normalize_base_url "$1" "$2")"
  AUTH_BASE_URL="$(normalize_base_url "$3" "$4")"
else
  usage
  exit 2
fi

TIMEOUT="${CALC_TEST_TIMEOUT:-20}"
VERBOSE="${CALC_TEST_VERBOSE:-0}"
SAVE_RESPONSES="${CALC_TEST_SAVE_RESPONSES:-0}"
AUTH_LOGIN_PATH="${CALC_TEST_AUTH_LOGIN_PATH:-/v1/signin}"
CREATE_USER="${CALC_TEST_CREATE_USER:-1}"
CREATE_SECOND_USER="${CALC_TEST_CREATE_SECOND_USER:-1}"
DELETE_HISTORY="${CALC_TEST_DELETE_HISTORY:-1}"

ADMIN_USERNAME="${CALC_TEST_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${CALC_TEST_ADMIN_PASSWORD:-admin123}"

RUN_ID="$(date +%s)-$RANDOM"
TEST_USERNAME="${CALC_TEST_USERNAME:-calcuser_${RUN_ID}}"
TEST_EMAIL="${TEST_USERNAME}@example.com"
TEST_PASSWORD="${CALC_TEST_PASSWORD:-Test1234!Aa}"
SECOND_USERNAME="calcother_${RUN_ID}"
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

ACCESS_TOKEN=""
USER_ID=""
ADMIN_TOKEN=""
SECOND_TOKEN=""
SECOND_USER_ID=""
LAST_CALCULATION_ID=""

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

safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_'
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
                    lk = k.lower()
                    if lk in sensitive or 'token' in lk or 'secret' in lk or 'password' in lk:
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
  cat "$TMP_DIR/$(safe_name "$1").path" 2>/dev/null || true
}

last_code() {
  cat "$TMP_DIR/$(safe_name "$1").code" 2>/dev/null || true
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
  local outfile="$TMP_DIR/$(safe_name "$name").json"
  local req_id="req-$(new_uuid | tr -d '-')"
  local trace_id="trace-$(new_uuid | tr -d '-')"
  local http_code curl_exit
  local accept_header="application/json"

  # /docs is intentionally text/html. Sending only Accept: application/json can
  # trigger content-negotiation failures in Spring because the route produces HTML.
  if [ "$path" = "/docs" ]; then
    accept_header="text/html,application/xhtml+xml,*/*"
  fi

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

  if [ "$token" != "" ]; then
    curl_args+=( -H "Authorization: Bearer $token" )
  fi

  if [ "$body" != "" ]; then
    curl_args+=( -H "Content-Type: application/json" -d "$body" )
  fi

  http_code="$(curl "${curl_args[@]}" 2>"$outfile.curlerr")"
  curl_exit=$?

  echo "$outfile" > "$TMP_DIR/$(safe_name "$name").path"
  echo "$http_code" > "$TMP_DIR/$(safe_name "$name").code"

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

calc_request() {
  request_base "$CALC_BASE_URL" "$@"
}

auth_request() {
  request_base "$AUTH_BASE_URL" "$@"
}

assert_json_status_ok() {
  local name="$1"
  local file status
  file="$(last_file "$name")"
  if [ -z "$file" ]; then
    record_fail "$name JSON status" "response file not found"
    return 1
  fi
  status="$(json_status "$file")"
  if [ "$status" = "ok" ]; then
    record_pass "$name envelope status is ok"
  else
    record_fail "$name envelope status" "expected status=ok, got '$status'. Body: $(short_body "$file" | tr '\n' ' ' | cut -c1-700)"
  fi
}

assert_json_status_error() {
  local name="$1"
  local expected_error="$2"
  local file status error_code
  file="$(last_file "$name")"
  status="$(json_get "$file" "status")"
  error_code="$(json_get "$file" "error_code")"
  if [ "$status" = "error" ] && printf '%s' "$error_code" | grep -Eq "^($expected_error)$"; then
    record_pass "$name error envelope is $error_code"
  else
    record_fail "$name error envelope" "expected status=error and error_code=$expected_error, got status=$status error_code=$error_code. Body: $(short_body "$file" | tr '\n' ' ' | cut -c1-700)"
  fi
}

assert_result_number() {
  # assert_result_number <request_name> <expected_number> [tolerance]
  local name="$1"
  local expected="$2"
  local tolerance="${3:-0.000001}"
  local file
  file="$(last_file "$name")"
  python3 - "$file" "$expected" "$tolerance" <<'PY'
import json, sys, decimal
file_path, expected, tolerance = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    obj = json.load(open(file_path, encoding='utf-8'))
    value = obj.get('data', {}).get('result')
    if value is None:
        print("FAIL missing data.result")
        sys.exit(1)
    v = decimal.Decimal(str(value))
    e = decimal.Decimal(str(expected))
    t = decimal.Decimal(str(tolerance))
    if abs(v - e) <= t:
        print("OK")
        sys.exit(0)
    print(f"FAIL expected {e}, got {v}")
except Exception as exc:
    print(f"FAIL {exc}")
    sys.exit(1)
PY
  local out=$?
  local msg
  msg="$(python3 - "$file" "$expected" "$tolerance" <<'PY'
import json, sys, decimal
file_path, expected, tolerance = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    obj = json.load(open(file_path, encoding='utf-8'))
    value = obj.get('data', {}).get('result')
    if value is None:
        print("missing data.result")
        sys.exit(0)
    v = decimal.Decimal(str(value))
    e = decimal.Decimal(str(expected))
    t = decimal.Decimal(str(tolerance))
    if abs(v - e) <= t:
        print(f"result {v} matches expected {e}")
    else:
        print(f"expected {e}, got {v}")
except Exception as exc:
    print(str(exc))
PY
)"
  if [ "$out" -eq 0 ]; then
    record_pass "$name result matches expected $expected"
  else
    record_fail "$name result mismatch" "$msg"
  fi
}

assert_field_not_empty() {
  local name="$1"
  local path="$2"
  local label="$3"
  local file value
  file="$(last_file "$name")"
  value="$(json_get "$file" "$path")"
  if [ "$value" != "" ]; then
    record_pass "$label extracted"
  else
    record_fail "$label extracted" "missing JSON path: $path"
  fi
}

print_header() {
  echo "${BOLD}${BLUE}Calculator Service API Smoke Test${RESET}"
  echo "Calculator Base URL: $CALC_BASE_URL"
  echo "Auth Base URL:       $AUTH_BASE_URL"
  echo "Auth Login:          $AUTH_LOGIN_PATH"
  echo "Timeout:             ${TIMEOUT}s"
  echo "Run ID:              $RUN_ID"
  echo "Create test user:    $CREATE_USER"
  echo "Delete history:      $DELETE_HISTORY"
  echo
}

signup_user() {
  local username="$1"
  local email="$2"
  local password="$3"
  local name="$4"
  local body
  body=$(cat <<JSON
{
  "username": "$username",
  "email": "$email",
  "password": "$password",
  "full_name": "$name",
  "birthdate": "1998-05-20",
  "gender": "male",
  "account_type": "user"
}
JSON
)
  auth_request "auth signup $username" "POST" "/v1/signup" "200|201|409" "$body" ""
}

signin_user() {
  local username="$1"
  local password="$2"
  local device="$3"
  local name="$4"
  local body
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
  if [ "$CREATE_USER" = "1" ]; then
    signup_user "$TEST_USERNAME" "$TEST_EMAIL" "$TEST_PASSWORD" "Calculator Smoke Test User"
  fi

  signin_user "$TEST_USERNAME" "$TEST_PASSWORD" "calculator-smoke-$RUN_ID" "auth primary user signin"
  local file role tenant
  file="$(last_file "auth primary user signin")"
  ACCESS_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  USER_ID="$(json_get_any "$file" "data.user.id" "data.user.user_id" "user.id" "user.user_id" "sub")"
  role="$(json_get_any "$file" "data.user.role" "user.role" "role")"
  tenant="$(json_get_any "$file" "data.user.tenant" "user.tenant" "tenant")"

  if [ "$ACCESS_TOKEN" = "" ]; then
    record_fail "primary user access token extracted" "No token found. Set CALC_TEST_USERNAME/CALC_TEST_PASSWORD or keep CALC_TEST_CREATE_USER=1."
    return 1
  fi
  record_pass "primary user access token extracted"

  if [ "$USER_ID" = "" ]; then
    record_fail "primary user id extracted" "No user id found from signin response."
  else
    record_pass "primary user id extracted: $USER_ID"
  fi

  if [ "$role" = "user" ]; then
    record_pass "primary user role is user"
  else
    record_fail "primary user role is user" "role=$role tenant=$tenant"
  fi
}

login_admin_token() {
  local body file role admin_status
  body=$(cat <<JSON
{
  "username_or_email": "$ADMIN_USERNAME",
  "password": "$ADMIN_PASSWORD",
  "device_id": "calculator-smoke-admin-$RUN_ID"
}
JSON
)
  auth_request "auth admin signin" "POST" "$AUTH_LOGIN_PATH" "200|401|403" "$body" ""
  file="$(last_file "auth admin signin")"
  ADMIN_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  role="$(json_get_any "$file" "data.user.role" "user.role" "role")"
  admin_status="$(json_get_any "$file" "data.user.admin_status" "user.admin_status" "admin_status")"

  if [ "$ADMIN_TOKEN" = "" ]; then
    record_skip "admin token extracted" "admin signin failed or token unavailable. Set CALC_TEST_ADMIN_USERNAME/CALC_TEST_ADMIN_PASSWORD if needed."
    return 0
  fi
  record_pass "admin token extracted"

  if [ "$role" = "admin" ] && [ "$admin_status" = "approved" ]; then
    record_pass "admin token is approved admin"
  else
    record_skip "admin token is approved admin" "role=$role admin_status=$admin_status"
  fi
}

login_second_user() {
  if [ "$CREATE_SECOND_USER" != "1" ]; then
    record_skip "second user token" "CALC_TEST_CREATE_SECOND_USER is not 1"
    return 0
  fi
  signup_user "$SECOND_USERNAME" "$SECOND_EMAIL" "$SECOND_PASSWORD" "Calculator Smoke Test Second User"
  signin_user "$SECOND_USERNAME" "$SECOND_PASSWORD" "calculator-smoke-second-$RUN_ID" "auth second user signin"
  local file
  file="$(last_file "auth second user signin")"
  SECOND_TOKEN="$(json_get_any "$file" "data.tokens.access_token" "data.access_token" "access_token" "token")"
  SECOND_USER_ID="$(json_get_any "$file" "data.user.id" "data.user.user_id" "user.id" "user.user_id" "sub")"

  if [ "$SECOND_TOKEN" = "" ]; then
    record_skip "second user token extracted" "second user token unavailable"
  else
    record_pass "second user token extracted"
  fi

  if [ "$SECOND_USER_ID" = "" ]; then
    record_skip "second user id extracted" "second user id unavailable"
  else
    record_pass "second user id extracted: $SECOND_USER_ID"
  fi
}

calc_operation() {
  local operation="$1"
  local operands_json="$2"
  local expected="$3"
  local tolerance="${4:-0.000001}"
  local name="calculate $operation $operands_json"
  local body
  body=$(cat <<JSON
{
  "operation": "$operation",
  "operands": $operands_json
}
JSON
)
  calc_request "$name" "POST" "/v1/calculator/calculate" "200" "$body" "$ACCESS_TOKEN"
  assert_json_status_ok "$name"
  assert_result_number "$name" "$expected" "$tolerance"

  local file calc_id
  file="$(last_file "$name")"
  calc_id="$(json_get "$file" "data.calculation_id")"
  if [ "$calc_id" != "" ]; then
    LAST_CALCULATION_ID="$calc_id"
  fi
}

calc_expression() {
  local expression="$1"
  local expected="$2"
  local tolerance="${3:-0.000001}"
  local name="calculate expression $expression"
  local body
  body=$(cat <<JSON
{
  "expression": "$expression"
}
JSON
)
  calc_request "$name" "POST" "/v1/calculator/calculate" "200" "$body" "$ACCESS_TOKEN"
  assert_json_status_ok "$name"
  assert_result_number "$name" "$expected" "$tolerance"

  local file calc_id
  file="$(last_file "$name")"
  calc_id="$(json_get "$file" "data.calculation_id")"
  if [ "$calc_id" != "" ]; then
    LAST_CALCULATION_ID="$calc_id"
  fi
}

calc_bad_request() {
  local name="$1"
  local body="$2"
  local expected_error="${3:-CALC_.*|BAD_REQUEST|VALIDATION_ERROR}"
  calc_request "$name" "POST" "/v1/calculator/calculate" "400" "$body" "$ACCESS_TOKEN"
  assert_json_status_error "$name" "$expected_error"
}

print_header

# Auth preflight.
auth_request "auth hello" "GET" "/hello" "200" "" ""
auth_request "auth health" "GET" "/health" "200|503" "" ""

login_primary_user
login_admin_token
login_second_user

if [ "$ACCESS_TOKEN" = "" ] || [ "$USER_ID" = "" ]; then
  echo
  echo "Cannot continue calculator checks because primary user token or user id is missing."
  exit 1
fi

# Public calculator routes.
calc_request "calculator hello" "GET" "/hello" "200" "" ""
assert_json_status_ok "calculator hello"

calc_request "calculator health" "GET" "/health" "200" "" ""
assert_json_status_ok "calculator health"

calc_request "calculator docs" "GET" "/docs" "200" "" ""

# Rejected public routes.
calc_request "calculator root rejected" "GET" "/" "404" "" ""
calc_request "calculator live rejected" "GET" "/live" "404" "" ""
calc_request "calculator ready rejected" "GET" "/ready" "404" "" ""
calc_request "calculator healthy rejected" "GET" "/healthy" "404" "" ""
calc_request "calculator openapi json rejected" "GET" "/openapi.json" "404" "" ""
calc_request "calculator v3 api docs rejected" "GET" "/v3/api-docs" "404" "" ""
calc_request "calculator swagger ui rejected" "GET" "/swagger-ui/index.html" "404" "" ""
calc_request "calculator swagger html rejected" "GET" "/swagger-ui.html" "404" "" ""

# AuthZ checks.
calc_request "operations without token" "GET" "/v1/calculator/operations" "401" "" ""
assert_json_status_error "operations without token" "UNAUTHORIZED"

calc_request "operations invalid token" "GET" "/v1/calculator/operations" "401" "" "not-a-valid-jwt"
assert_json_status_error "operations invalid token" "UNAUTHORIZED"

# Operations list.
calc_request "operations with token" "GET" "/v1/calculator/operations" "200" "" "$ACCESS_TOKEN"
assert_json_status_ok "operations with token"

OPS_FILE="$(last_file "operations with token")"
python3 - "$OPS_FILE" <<'PY'
import json, sys
expected = {
    "ADD", "SUBTRACT", "MULTIPLY", "DIVIDE", "MODULO", "POWER", "SQRT",
    "PERCENTAGE", "SIN", "COS", "TAN", "LOG", "LN", "ABS", "ROUND",
    "FLOOR", "CEIL", "FACTORIAL"
}
obj = json.load(open(sys.argv[1], encoding='utf-8'))
actual = {x.get("operation") for x in obj.get("data", []) if isinstance(x, dict)}
missing = sorted(expected - actual)
extra = sorted(actual - expected)
if missing or extra:
    print("FAIL missing=%s extra=%s" % (missing, extra))
    sys.exit(1)
print("OK")
PY
if [ "$?" -eq 0 ]; then
  record_pass "operations list contains all supported operations"
else
  record_fail "operations list contains all supported operations" "$(python3 - "$OPS_FILE" <<'PY'
import json, sys
expected = {
    "ADD", "SUBTRACT", "MULTIPLY", "DIVIDE", "MODULO", "POWER", "SQRT",
    "PERCENTAGE", "SIN", "COS", "TAN", "LOG", "LN", "ABS", "ROUND",
    "FLOOR", "CEIL", "FACTORIAL"
}
try:
    obj = json.load(open(sys.argv[1], encoding='utf-8'))
    actual = {x.get("operation") for x in obj.get("data", []) if isinstance(x, dict)}
    print("missing=%s extra=%s" % (sorted(expected - actual), sorted(actual - expected)))
except Exception as exc:
    print(exc)
PY
)"
fi

# Successful operation-mode calculations.
calc_operation "ADD" "[10,20,5]" "35"
calc_operation "SUBTRACT" "[100,30,20]" "50"
calc_operation "MULTIPLY" "[2,3,4]" "24"
calc_operation "DIVIDE" "[100,4]" "25"
calc_operation "MODULO" "[10,3]" "1"
calc_operation "POWER" "[2,8]" "256"
calc_operation "SQRT" "[81]" "9"
calc_operation "PERCENTAGE" "[10,200]" "20"
calc_operation "SIN" "[30]" "0.5" "0.0001"
calc_operation "COS" "[60]" "0.5" "0.0001"
calc_operation "TAN" "[45]" "1" "0.0001"
calc_operation "LOG" "[1000]" "3" "0.0001"
calc_operation "LN" "[1]" "0" "0.0001"
calc_operation "ABS" "[-123.45]" "123.45"
calc_operation "ROUND" "[12.6]" "13"
calc_operation "FLOOR" "[12.9]" "12"
calc_operation "CEIL" "[12.1]" "13"
calc_operation "FACTORIAL" "[5]" "120"

# Successful expression-mode calculations.
calc_expression "sqrt(16)+(10+5)*3" "49"
calc_expression "2^8" "256"
calc_expression "abs(-15)+floor(3.9)+ceil(4.1)" "23"
calc_expression "log(1000)+ln(1)+round(2.6)" "6" "0.0001"

# Invalid requests.
calc_bad_request "calculate both operation and expression rejected" '{
  "operation": "ADD",
  "operands": [1, 2],
  "expression": "1+2"
}' "CALC_.*|VALIDATION_ERROR|BAD_REQUEST"

calc_bad_request "calculate missing mode rejected" '{}' "CALC_.*|VALIDATION_ERROR|BAD_REQUEST"

calc_bad_request "calculate divide by zero rejected" '{
  "operation": "DIVIDE",
  "operands": [10, 0]
}' "CALC_DIVIDE_BY_ZERO|CALC_.*|BAD_REQUEST"

calc_bad_request "calculate modulo by zero rejected" '{
  "operation": "MODULO",
  "operands": [10, 0]
}' "CALC_MODULO_BY_ZERO|CALC_DIVIDE_BY_ZERO|CALC_.*|BAD_REQUEST"

calc_bad_request "calculate negative sqrt rejected" '{
  "operation": "SQRT",
  "operands": [-1]
}' "CALC_.*|BAD_REQUEST"

calc_bad_request "calculate log nonpositive rejected" '{
  "operation": "LOG",
  "operands": [0]
}' "CALC_.*|BAD_REQUEST"

calc_bad_request "calculate factorial negative rejected" '{
  "operation": "FACTORIAL",
  "operands": [-1]
}' "CALC_.*|BAD_REQUEST"

calc_bad_request "calculate invalid expression rejected" '{
  "expression": "sqrt("
}' "CALC_INVALID_EXPRESSION|CALC_.*|BAD_REQUEST"

calc_bad_request "calculate invalid operation rejected" '{
  "operation": "NOPE",
  "operands": [1, 2]
}' "CALC_INVALID_OPERATION|VALIDATION_ERROR|CALC_.*|BAD_REQUEST"

# History and record lookup.
calc_request "history current user" "GET" "/v1/calculator/history?limit=50" "200" "" "$ACCESS_TOKEN"
assert_json_status_ok "history current user"

calc_request "history current user low limit" "GET" "/v1/calculator/history?limit=1" "200" "" "$ACCESS_TOKEN"
assert_json_status_ok "history current user low limit"

calc_request "history own user path" "GET" "/v1/calculator/history/$USER_ID?limit=50" "200" "" "$ACCESS_TOKEN"
assert_json_status_ok "history own user path"

if [ "$LAST_CALCULATION_ID" != "" ]; then
  calc_request "get created calculation record" "GET" "/v1/calculator/records/$LAST_CALCULATION_ID" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "get created calculation record"
else
  record_fail "get created calculation record" "LAST_CALCULATION_ID is empty"
fi

calc_request "get missing calculation record" "GET" "/v1/calculator/records/missing-calc-$(new_uuid)" "404" "" "$ACCESS_TOKEN"
assert_json_status_error "get missing calculation record" "CALC_RECORD_NOT_FOUND|CALCULATION_NOT_FOUND|NOT_FOUND"

# Cross-user checks.
if [ "$SECOND_TOKEN" != "" ] && [ "$SECOND_USER_ID" != "" ]; then
  calc_request "second user forbidden reading primary history" "GET" "/v1/calculator/history/$USER_ID?limit=10" "403" "" "$SECOND_TOKEN"
  assert_json_status_error "second user forbidden reading primary history" "FORBIDDEN|TENANT_MISMATCH|ACCESS_DENIED"
else
  record_skip "second user forbidden reading primary history" "second user token/id unavailable"
fi

if [ "$ADMIN_TOKEN" != "" ]; then
  calc_request "approved admin can read primary history" "GET" "/v1/calculator/history/$USER_ID?limit=10" "200|403" "" "$ADMIN_TOKEN"
  ADMIN_CROSS_CODE="$(last_code "approved admin can read primary history")"
  if [ "$ADMIN_CROSS_CODE" = "200" ]; then
    assert_json_status_ok "approved admin can read primary history"
  else
    record_skip "approved admin can read primary history permission" "admin token was accepted by auth, but calculator returned 403. Verify admin_status=approved and shared JWT claims."
  fi
else
  record_skip "approved admin can read primary history" "admin token unavailable"
fi

# Soft-clear own history. Safe with generated users; optionally disabled for existing users.
if [ "$DELETE_HISTORY" = "1" ]; then
  calc_request "delete current user history" "DELETE" "/v1/calculator/history" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "delete current user history"

  calc_request "history after delete current user" "GET" "/v1/calculator/history?limit=50" "200" "" "$ACCESS_TOKEN"
  assert_json_status_ok "history after delete current user"
else
  record_skip "delete current user history" "CALC_TEST_DELETE_HISTORY is not 1"
fi

# Health after all API checks.
calc_request "calculator health after api checks" "GET" "/health" "200" "" ""
assert_json_status_ok "calculator health after api checks"

echo
printf "%sSummary:%s %s total, %s passed, %s failed, %s skipped\n" "$BOLD" "$RESET" "$TEST_COUNT" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
echo "Calculator Base URL: $CALC_BASE_URL"
echo "Auth Base URL:       $AUTH_BASE_URL"
echo "Test username:       $TEST_USERNAME"
echo "Primary user id:     $USER_ID"
echo "Second user id:      $SECOND_USER_ID"
echo "Last calculation id: $LAST_CALCULATION_ID"
echo "Delete history:      $DELETE_HISTORY"
if [ "$SAVE_RESPONSES" = "1" ]; then
  echo "Response files:      $TMP_DIR"
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo
  echo "One or more calculator service checks failed. Review the failure messages above."
  exit 1
fi

echo
printf "%sAll required calculator service checks passed.%s\n" "$GREEN" "$RESET"
exit 0



# chmod +x calculator_service_api_smoke_test.sh
# ./calculator_service_api_smoke_test.sh 192.168.56.100 2020 192.168.56.100 6060 >> smoke_test_output.txt 2>&1
# ./calculator_service_api_smoke_test.sh http://192.168.56.100:2020 http://192.168.56.100:6060 >> smoke_test_output.txt 2>&1
# CALC_TEST_VERBOSE=1 CALC_TEST_SAVE_RESPONSES=1 ./calculator_service_api_smoke_test.sh 192.168.56.100 2020 192.168.56.100 6060 >> smoke_test_output.txt 2>&1