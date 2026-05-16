# Calculator service APM verification

The application emits Elastic APM transactions, spans, logs correlation IDs, and dependency checks for PostgreSQL, Redis, Kafka, S3, MongoDB, APM Server, and Elasticsearch.

To make Kibana's Dependencies tab populate quickly, generate traffic:

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

Then open Kibana:

```text
Observability > APM > Service inventory > calculator_service
```

Expected app-provided views:

- Overview
- Transactions
- Dependencies
- Errors
- Metrics produced by APM agent/JVM/runtime
- Logs correlation fields when logs are ingested into Elasticsearch
- Service map when communicating services are also instrumented

Infrastructure inventory, hosts, TLS certificates, monitors, synthetics, alerts, SLOs, cases, logs anomalies, logs categories, streams, and dashboards require Kibana features plus Elastic Agent/Metricbeat/Filebeat/Synthetics or saved objects configured outside the application container.
