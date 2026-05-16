#!/usr/bin/env bash
set -euo pipefail

CALCULATOR_BASE_URL="${CALCULATOR_BASE_URL:-http://localhost:2020}"
CALCULATOR_TOKEN="${CALCULATOR_TOKEN:-}"
COUNT="${COUNT:-30}"
FORWARDED_PROTO="${FORWARDED_PROTO:-}"

headers=(-H "accept: application/json")
if [ -n "$FORWARDED_PROTO" ]; then headers+=(-H "X-Forwarded-Proto: $FORWARDED_PROTO"); fi
if [ -n "$CALCULATOR_TOKEN" ]; then headers+=(-H "Authorization: Bearer $CALCULATOR_TOKEN"); fi

for i in $(seq 1 "$COUNT"); do
  curl -fsS "${headers[@]}" "$CALCULATOR_BASE_URL/hello" >/dev/null || true
  curl -fsS "${headers[@]}" "$CALCULATOR_BASE_URL/health" >/dev/null || true
  if [ -n "$CALCULATOR_TOKEN" ]; then
    curl -fsS "${headers[@]}" -H "Content-Type: application/json" \
      -d '{"operation":"ADD","operands":[10,20,5]}' \
      "$CALCULATOR_BASE_URL/v1/calculator/calculate" >/dev/null || true
    curl -fsS "${headers[@]}" "$CALCULATOR_BASE_URL/v1/calculator/history?limit=5" >/dev/null || true
  fi
  sleep 1
done

echo "Generated calculator_service APM traffic. Check Kibana APM > calculator_service > Dependencies with Last 15/30 minutes."
