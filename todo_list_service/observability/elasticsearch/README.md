# Elasticsearch verification

This service emits APM traces/errors/metrics through APM Server and structured logs through MongoDB/stdout. Use this helper to verify Elasticsearch receives APM indices/data streams:

```bash
TODO_ELASTICSEARCH_URL=http://192.168.56.100:9200 \
TODO_ELASTICSEARCH_USERNAME=elastic \
TODO_ELASTICSEARCH_PASSWORD='<password>' \
./observability/elasticsearch/setup_todo_service_elasticsearch.sh
```

Kibana UI pages such as Overview, Dependencies, Infrastructure, Hosts, Logs, Alerts, SLOs, Cases, Synthetics, TLS Certificates, and Dashboards require Kibana and the relevant Elastic integrations/agents. Application code can emit APM/log data, but it cannot create host metrics or synthetic monitors by itself.
