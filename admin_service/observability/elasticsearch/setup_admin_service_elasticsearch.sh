#!/usr/bin/env bash
set -eu

: "${ADMIN_ELASTICSEARCH_URL:=http://192.168.56.100:9200}"
: "${ADMIN_ELASTICSEARCH_USERNAME:=elastic}"
: "${ADMIN_ELASTICSEARCH_PASSWORD:?ADMIN_ELASTICSEARCH_PASSWORD is required}"

echo "Checking Elasticsearch cluster health..."
curl -fsS -u "$ADMIN_ELASTICSEARCH_USERNAME:$ADMIN_ELASTICSEARCH_PASSWORD" \
  "$ADMIN_ELASTICSEARCH_URL/_cluster/health?pretty"

echo
echo "Checking APM indices..."
curl -fsS -u "$ADMIN_ELASTICSEARCH_USERNAME:$ADMIN_ELASTICSEARCH_PASSWORD" \
  "$ADMIN_ELASTICSEARCH_URL/_cat/indices/traces-apm*,metrics-apm*,logs-apm*?v" || true

echo
echo "Checking admin_service matching indices..."
curl -fsS -u "$ADMIN_ELASTICSEARCH_USERNAME:$ADMIN_ELASTICSEARCH_PASSWORD" \
  "$ADMIN_ELASTICSEARCH_URL/_cat/indices/*admin_service*?v" || true
