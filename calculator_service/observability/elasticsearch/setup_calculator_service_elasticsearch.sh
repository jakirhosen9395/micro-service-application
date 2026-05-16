#!/usr/bin/env bash
set -euo pipefail

ES_URL="${CALC_ELASTICSEARCH_URL:-${ELASTICSEARCH_URL:-http://localhost:9200}}"
ES_USER="${CALC_ELASTICSEARCH_USERNAME:-${ELASTICSEARCH_USERNAME:-elastic}}"
ES_PASS="${CALC_ELASTICSEARCH_PASSWORD:-${ELASTICSEARCH_PASSWORD:-}}"

AUTH=()
if [ -n "$ES_USER" ]; then AUTH=(-u "$ES_USER:$ES_PASS"); fi

echo "Checking Elasticsearch at $ES_URL"
curl -fsS "${AUTH[@]}" "$ES_URL/_cluster/health?pretty"
echo
echo "APM/service docs for calculator_service:"
curl -fsS "${AUTH[@]}" "$ES_URL/traces-apm*/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{"size":0,"query":{"term":{"service.name":"calculator_service"}},"aggs":{"types":{"terms":{"field":"processor.event","size":10}}}}'
