# todo_list_service APM traffic

Run this after the service is up to force transactions and dependency spans into Elastic APM/Kibana:

```bash
TODO_BASE_URL=http://192.168.56.50:3030 \
TODO_TOKEN='<valid-user-jwt>' \
COUNT=30 \
./observability/apm/generate_todo_dependency_traffic.sh
```

For stage/prod over local HTTP ports:

```bash
FORWARDED_PROTO=https ./observability/apm/generate_todo_dependency_traffic.sh
```

Expected APM views after traffic:

- Service inventory: `todo_list_service`
- Transactions: `/hello`, `/health`, `/v1/todos`
- Dependencies: PostgreSQL, Redis, Kafka, S3, MongoDB, APM Server, Elasticsearch when those code paths run
- Errors: only real unhandled/server-side failures, not handled validation/401/403/404 responses

Host infrastructure, container CPU/RAM/disk/network, Synthetics, TLS certificates, SLOs, alerts, cases, log anomaly jobs, and custom dashboards require Kibana plus Elastic Agent/Metricbeat/Filebeat/Synthetics configuration outside the application container.
