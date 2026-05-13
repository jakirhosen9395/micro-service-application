import { describe, expect, it } from "vitest";
import { auditEventKey, reportFileKey } from "../src/storage/paths.js";
import { createEventEnvelope } from "../src/events/envelope.js";
import { redactSecrets } from "../src/logging/redaction.js";
import { listReportTypes } from "../src/report-types/registry.js";
import type { AppConfig } from "../src/config/config.js";

const config = {
  service: { name: "report_service", environment: "development", nodeEnv: "development", version: "v1.0.0", tenant: "dev", host: "0.0.0.0", port: 8080 },
  jwt: { secret: "test", issuer: "auth", audience: "micro-app", algorithm: "HS256", leewaySeconds: 5 },
  postgres: { host: "x", port: 5432, user: "u", password: "p", database: "d", schema: "report", poolSize: 10, maxOverflow: 10, migrationMode: "auto" },
  redis: { host: "x", port: 6379, password: "p", db: 0, cacheTtlSeconds: 300 },
  kafka: { bootstrapServers: ["x:9092"], eventsTopic: "report.events", deadLetterTopic: "report.dead-letter", consumerGroup: "report_service-development", consumeTopics: [], autoCreateTopics: true },
  s3: { endpoint: "http://x:9000", accessKey: "a", secretKey: "s", region: "us-east-1", forcePathStyle: true, bucket: "microservice", auditPrefix: "report_service/development", reportPrefix: "report_service/development" },
  mongo: { host: "x", port: 27017, username: "u", password: "p", database: "micro_services_logs", authSource: "admin", logCollection: "report_service_development_logs" },
  apm: { serverUrl: "http://x:8200", secretToken: "t", transactionSampleRate: 1, captureBody: "errors" },
  elasticsearch: { url: "http://x:9200", username: "elastic", password: "p" },
  kibana: { url: "http://x:5601", username: "elastic", password: "p" },
  logging: { level: "info", format: "pretty-json", logstashEnabled: false, logstashHost: "x", logstashPort: 5000 },
  cors: { allowedOrigins: [], allowedMethods: [], allowedHeaders: [], allowCredentials: true, maxAgeSeconds: 3600 },
  security: { requireHttps: false, secureCookies: false, requireTenantMatch: true },
  report: { bullmqQueueName: "report-generation", workerConcurrency: 3, queueRemoveOnCompleteAgeSeconds: 86400, queueRemoveOnFailAgeSeconds: 604800, queueJobTimeoutMs: 300000, generationMaxRows: 100000, previewMaxBytes: 1048576, downloadContentDisposition: "attachment", workerShutdownGraceMs: 30000 }
} satisfies AppConfig;

describe("canonical contract functions", () => {
  it("builds canonical report S3 file keys", () => {
    expect(reportFileKey(config, "dev", "user-1", "report-1", "pdf", new Date("2026-05-09T10:15:30Z"))).toBe("report_service/development/tenant/dev/users/user-1/reports/2026/05/09/report-1.pdf");
  });

  it("builds canonical audit S3 event keys", () => {
    expect(auditEventKey(config, "dev", "actor-1", "report.completed", "evt-1", new Date("2026-05-09T10:15:30Z"))).toBe("report_service/development/tenant/dev/users/actor-1/events/2026/05/09/101530_report_completed_evt-1.json");
  });

  it("creates canonical event envelopes", () => {
    const event = createEventEnvelope(config, { eventType: "report.requested", tenant: "dev", userId: "u1", actorId: "u1", aggregateType: "report", aggregateId: "r1", requestId: "req", traceId: "trace", correlationId: "corr", payload: { ok: true } });
    expect(event.service).toBe("report_service");
    expect(event.event_version).toBe("1.0");
    expect(event.aggregate_type).toBe("report");
    expect(event.aggregate_id).toBe("r1");
    expect(event.event_id).toMatch(/^evt-/);
  });

  it("redacts secret-shaped log fields", () => {
    expect(redactSecrets({ password: "x", nested: { authorization: "Bearer token", keep: "ok" } })).toEqual({ password: "[REDACTED]", nested: { authorization: "[REDACTED]", keep: "ok" } });
  });

  it("registers all required and advanced report types", () => {
    const names = listReportTypes().map((item) => item.report_type);
    for (const required of ["calculator_history_report", "todo_summary_report", "user_activity_report", "full_user_report", "user_profile_report", "user_dashboard_report", "user_access_grants_report", "cross_user_access_report", "admin_decision_report", "admin_audit_report", "calculator_summary_report", "calculator_operations_report", "todo_activity_report", "todo_status_report", "productivity_summary_report", "full_application_activity_report", "report_inventory_report", "report_generation_health_report"]) {
      expect(names).toContain(required);
    }
  });
});
