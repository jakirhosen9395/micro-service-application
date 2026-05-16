# Kibana visibility notes

After APM Server receives data from `todo_list_service`, Kibana can show:

- Applications / Service inventory
- Overview
- Transactions
- Traces
- Dependencies
- Errors
- JVM/runtime metrics emitted by the APM Java agent
- Logs when logs are shipped to Elasticsearch

The following features are not created by application code alone and require Kibana/Elastic configuration:

- Alerts
- SLOs
- Cases
- AI Assistant
- Streams
- Discover data views
- Logs UI, log categories, log anomaly jobs
- Infrastructure inventory
- Metrics Explorer
- Hosts
- Synthetics monitors
- TLS Certificates
- User Experience/RUM
- Custom dashboards

Install Elastic Agent or Metricbeat/Filebeat/Synthetics and create Kibana saved objects/data views for those UI pages.
