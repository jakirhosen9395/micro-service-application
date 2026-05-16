#!/usr/bin/env bash
set -eu

TODO_BASE_URL="${TODO_BASE_URL:-http://localhost:3030}"
TODO_TOKEN="${TODO_TOKEN:-}"
COUNT="${COUNT:-30}"
FORWARDED_PROTO="${FORWARDED_PROTO:-}"

headers=(-H "accept: application/json" -H "X-Request-ID: dep-traffic-$RANDOM")
if [ -n "$FORWARDED_PROTO" ]; then headers+=( -H "X-Forwarded-Proto: $FORWARDED_PROTO" ); fi
if [ -n "$TODO_TOKEN" ]; then headers+=( -H "Authorization: Bearer $TODO_TOKEN" ); fi

for i in $(seq 1 "$COUNT"); do
  curl -fsS "${TODO_BASE_URL%/}/health" "${headers[@]}" >/dev/null || true
  curl -fsS "${TODO_BASE_URL%/}/hello" "${headers[@]}" >/dev/null || true
  if [ -n "$TODO_TOKEN" ]; then
    curl -fsS "${TODO_BASE_URL%/}/v1/todos?limit=5&offset=0" "${headers[@]}" >/dev/null || true
  fi
  sleep 1
done

echo "Generated todo_list_service dependency traffic against ${TODO_BASE_URL%/}."
