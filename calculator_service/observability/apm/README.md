# Calculator service APM verification

The calculator service emits Elastic APM HTTP transactions, framework spans, manual dependency spans, log-correlation IDs, JVM/runtime metrics, and error capture for unexpected failures.

## What the application emits

The application code can emit data for these Kibana areas when APM Server/Elasticsearch/Kibana are available:

- Observability overview data for `calculator_service`
- Applications / Service inventory
- Transactions for `/hello`, `/health`, `/docs`, and all `/v1/calculator/**` routes
- Traces and service-map edges when other instrumented services call or are called by instrumented clients
- Dependencies for PostgreSQL, Redis, Kafka, S3/MinIO, MongoDB, APM Server, and Elasticsearch when those code paths are exercised
- Errors for real unhandled failures and HTTP 500 failures
- JVM/runtime metrics produced by the Elastic Java agent
- Log correlation fields: `trace.id`, `transaction.id`, and `span.id`

Expected business errors such as validation failures, `401`, `403`, and `404` are intentionally ignored by APM error grouping through `ignore_exceptions`. They remain visible in structured logs and HTTP responses but should not pollute APM Errors.

## Generate dependency traffic

```bash
CALCULATOR_BASE_URL=http://192.168.56.50:2020 \
CALCULATOR_TOKEN='<valid-user-jwt>' \
COUNT=30 \
./observability/apm/generate_calculator_dependency_traffic.sh
```

For stage/prod over local HTTP host ports, add:

```bash
FORWARDED_PROTO=https
```

Then open:

```text
Kibana > Observability > APM > Service inventory > calculator_service
```

Use a time range such as **Last 15 minutes** or **Last 30 minutes**.

## Important Elastic limitation

The application can emit APM traces, spans, errors, dependency spans, JVM metrics, and correlated logs. The following Kibana areas require Elastic/Kibana setup outside the application container:

- Alerts
- SLOs
- Cases
- AI Assistant
- Streams
- Discover data views
- Logs ingestion and log data views
- Logs Anomalies
- Logs Categories
- Infrastructure inventory
- Metrics Explorer
- Hosts
- Synthetics
- Monitors
- TLS Certificates
- User Experience
- Custom Dashboards

For those, install and configure Kibana plus Elastic Agent, Fleet, Filebeat/Metricbeat, Docker/Kubernetes integration, Synthetics, and saved objects as needed. The application alone cannot create host CPU/RAM/disk/network metrics or browser user-experience data.
