# Elasticsearch verification

Use this when you have Elasticsearch/APM Server and want to verify calculator_service telemetry is arriving.

```bash
CALC_ELASTICSEARCH_URL=http://192.168.56.100:9200 \
CALC_ELASTICSEARCH_USERNAME=elastic \
CALC_ELASTICSEARCH_PASSWORD='<password>' \
./observability/elasticsearch/setup_calculator_service_elasticsearch.sh
```

This script verifies cluster health and whether APM documents for `calculator_service` exist.
