#!/usr/bin/env bash
set -eu

KIBANA_URL="${ADMIN_KIBANA_URL:-http://192.168.56.100:5601}"
KIBANA_USERNAME="${ADMIN_KIBANA_USERNAME:-elastic}"
KIBANA_PASSWORD="${ADMIN_KIBANA_PASSWORD:-}"

if [ -z "$KIBANA_PASSWORD" ]; then
  echo "ADMIN_KIBANA_PASSWORD is required."
  exit 2
fi

api() {
  method="$1"
  path="$2"
  body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS -u "$KIBANA_USERNAME:$KIBANA_PASSWORD" \
      -H 'kbn-xsrf: true' \
      -H 'Content-Type: application/json' \
      -X "$method" "$KIBANA_URL$path" \
      -d "$body"
  else
    curl -sS -u "$KIBANA_USERNAME:$KIBANA_PASSWORD" \
      -H 'kbn-xsrf: true' \
      -X "$method" "$KIBANA_URL$path"
  fi
  echo
}

create_data_view() {
  title="$1"
  name="$2"
  body=$(cat <<JSON
{
  "data_view": {
    "title": "$title",
    "name": "$name",
    "timeFieldName": "@timestamp"
  },
  "override": true
}
JSON
)
  api POST "/api/data_views/data_view" "$body" >/dev/null || true
  echo "Ensured data view: $name -> $title"
}

create_data_view "traces-apm*,apm-*" "Admin Service APM traces"
create_data_view "metrics-apm*,metrics-*" "Admin Service metrics"
create_data_view "logs-*,filebeat-*,admin_service_*" "Admin Service logs"

echo "Kibana data views requested. Open: $KIBANA_URL/app/apm/services/admin_service"
echo "For Infrastructure, install Elastic Agent or Metricbeat on the Docker host."
