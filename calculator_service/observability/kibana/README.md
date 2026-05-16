# Calculator service Kibana notes

Use this directory when Kibana is available. The application emits the telemetry; Kibana displays it.

Recommended Kibana checks:

1. Observability > APM > Service inventory > `calculator_service`
2. Transactions: call `/hello`, `/health`, `/docs`, and `/v1/calculator/calculate`
3. Dependencies: run `observability/apm/generate_calculator_dependency_traffic.sh`
4. Errors: trigger a real HTTP 500 only; expected `400`, `401`, `403`, and `404` are handled business/client errors and should not appear as APM error groups
5. Logs: ingest container stdout or MongoDB structured logs into Elasticsearch, then create data views for `logs-*` or your chosen index
6. Infrastructure/Hosts/Metrics Explorer: install Elastic Agent or Metricbeat with Docker/system integration on the host
7. Synthetics/Monitors/TLS Certificates: configure Kibana Synthetics separately
8. Alerts/SLOs/Cases/Dashboards: create Kibana saved objects or rules after telemetry is flowing
