# admin_service APM dependency visibility

Kibana's **APM > Dependencies** page is based on APM dependency/exit spans, not on `/health` JSON dependency keys and not on MongoDB log documents.

This build emits both normal Elastic APM custom spans and OpenTelemetry client activities for these dependencies:

- PostgreSQL / Npgsql / EF Core
- Redis / StackExchange.Redis
- Kafka produce, consume, commit, topic-admin operations
- MongoDB log inserts and index creation
- S3 audit writes and bucket checks
- APM Server and Elasticsearch HTTP checks

The app also sets `ELASTIC_APM_OPENTELEMETRY_BRIDGE_ENABLED=true` during startup so the Elastic .NET agent can ingest the ActivitySource dependency spans.

## Generate traffic

Dependencies only appear after transactions with dependency spans are ingested. Run this after the container starts:

```bash
ADMIN_BASE_URL=http://192.168.56.50:1010 \
ADMIN_TOKEN='<approved-admin-jwt>' \
COUNT=30 \
./observability/apm/generate_admin_dependency_traffic.sh
```

For stage/prod tested over local HTTP ports while HTTPS enforcement is enabled:

```bash
ADMIN_BASE_URL=http://192.168.56.50:1012 \
ADMIN_TOKEN='<approved-admin-jwt>' \
FORWARDED_PROTO=https \
COUNT=30 \
./observability/apm/generate_admin_dependency_traffic.sh
```

Then open Kibana:

```text
APM > Service inventory > admin_service > Dependencies
```

Use **Last 15 minutes** or **Last 30 minutes**, and choose the correct `environment` filter.

## Notes

- Infrastructure metrics in Kibana require Elastic Agent, Metricbeat, Docker metrics, Kubernetes metrics, or another infrastructure collector. The admin service can emit APM traces and application metrics, but it cannot by itself create host/container CPU, RAM, disk, or network metrics.
- Logs in Kibana require your MongoDB logs to be shipped/indexed into Elasticsearch or a log shipper configured for container stdout. MongoDB is the application log sink; Kibana reads Elasticsearch indices.
