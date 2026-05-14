#!/usr/bin/env bash
set -euo pipefail

ADMIN_BASE_URL="${ADMIN_BASE_URL:-http://192.168.56.50:1010}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
COUNT="${COUNT:-20}"
SLEEP_SECONDS="${SLEEP_SECONDS:-1}"
FORWARDED_PROTO="${FORWARDED_PROTO:-}"

headers=( -H "accept: application/json" )
if [ -n "$FORWARDED_PROTO" ]; then
  headers+=( -H "X-Forwarded-Proto: $FORWARDED_PROTO" )
fi
if [ -n "$ADMIN_TOKEN" ]; then
  headers+=( -H "Authorization: Bearer $ADMIN_TOKEN" )
fi

echo "Generating admin_service APM dependency traffic against $ADMIN_BASE_URL"
echo "COUNT=$COUNT SLEEP_SECONDS=$SLEEP_SECONDS"

for i in $(seq 1 "$COUNT"); do
  req="req-apm-deps-$i-$(date +%s)"
  curl -fsS "${ADMIN_BASE_URL%/}/health" \
    -H "X-Request-ID: $req" \
    -H "X-Trace-ID: trace-$req" \
    -H "X-Correlation-ID: $req" \
    "${headers[@]}" >/dev/null || true

  if [ -n "$ADMIN_TOKEN" ]; then
    curl -fsS "${ADMIN_BASE_URL%/}/v1/admin/dashboard" \
      -H "X-Request-ID: $req-dashboard" \
      -H "X-Trace-ID: trace-$req-dashboard" \
      -H "X-Correlation-ID: $req-dashboard" \
      "${headers[@]}" >/dev/null || true
  fi

  sleep "$SLEEP_SECONDS"
done

echo "Done. In Kibana, open APM > admin_service > Dependencies and use Last 15 minutes or Last 30 minutes."
