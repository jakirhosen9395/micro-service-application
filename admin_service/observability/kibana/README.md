# Admin Service Kibana / Elastic Observability

The admin service emits Elastic APM transactions, spans, errors, runtime metrics, ECS-compatible stdout logs, and MongoDB structured logs.

## What appears in Kibana

After the service receives traffic, Kibana APM should show:

- **Overview**: service health, latency, throughput, error rate for `admin_service`.
- **Transactions**: HTTP requests, startup initialization, outbox publish batches, Kafka consume transactions.
- **Dependencies**: PostgreSQL, Redis, Kafka, S3/MinIO, MongoDB, APM Server, Elasticsearch.
- **Errors**: real unhandled exceptions with stack traces and `error_code` labels.
- **Metrics**: .NET runtime/APM metrics. Host/container metrics require Elastic Agent, Metricbeat, Docker metrics, or Kubernetes metrics.
- **Infrastructure**: requires Elastic Agent/Metricbeat on the VM/container host.
- **Service map**: appears when APM services exchange trace context or are individually reporting to APM.
- **Logs**: stdout logs if collected by Elastic Agent/Filebeat, plus MongoDB log documents in `micro_services_logs.admin_service_<env>_logs`.
- **Alerts** and **Dashboards**: import or create them from Kibana using the script in this folder.

## Required runtime checks

Make at least one call to every important route so APM has data:

```bash
curl -i http://localhost:1010/hello
curl -i http://localhost:1010/health
curl -i -H "Authorization: Bearer <approved-admin-jwt>" http://localhost:1010/v1/admin/dashboard
```

For stage/prod over local HTTP ports, also pass:

```bash
-H "X-Forwarded-Proto: https"
```

## Import helper

`setup_admin_service_kibana.sh` creates basic data views for APM traces, APM metrics, and logs. It does not replace Elastic Agent or Metricbeat; those are required for host/container infrastructure metrics.

```bash
ADMIN_KIBANA_URL=http://192.168.56.100:5601 \
ADMIN_KIBANA_USERNAME=elastic \
ADMIN_KIBANA_PASSWORD='<password>' \
./observability/kibana/setup_admin_service_kibana.sh
```
