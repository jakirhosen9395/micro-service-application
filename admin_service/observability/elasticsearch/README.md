# admin_service Elasticsearch / APM observability

The application does not require `ADMIN_KIBANA_*` environment variables. It sends telemetry to `ADMIN_APM_SERVER_URL`; APM Server stores APM traces, dependencies, errors, metrics, and service-map data in Elasticsearch. Structured application logs are still written to MongoDB and stdout.

Use Kibana only as an external viewer if it exists in your platform. Without Kibana, the service can still send data to Elasticsearch/APM, but the UI sections such as Overview, Transactions, Dependencies, Errors, Metrics, Infrastructure, Service map, Logs, Alerts, and Dashboards cannot be displayed because those are Kibana UI features.

## Verify Elasticsearch from the VM

```bash
curl -u elastic:$ADMIN_ELASTICSEARCH_PASSWORD http://192.168.56.100:9200/_cluster/health?pretty
curl -u elastic:$ADMIN_ELASTICSEARCH_PASSWORD 'http://192.168.56.100:9200/_cat/indices/*admin_service*?v'
curl -u elastic:$ADMIN_ELASTICSEARCH_PASSWORD 'http://192.168.56.100:9200/_cat/indices/traces-apm*,metrics-apm*,logs-apm*?v'
```

## Generate admin_service APM traffic

```bash
curl -i http://localhost:1010/hello
curl -i http://localhost:1010/health
curl -i -H "Authorization: Bearer <approved-admin-jwt>" http://localhost:1010/v1/admin/dashboard
```
