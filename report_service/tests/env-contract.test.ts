import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

function text(file: string): string {
  return readFileSync(resolve(process.cwd(), file), "utf8");
}

function keysFor(file: string): string[] {
  return text(file)
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#") && line.includes("="))
    .map((line) => line.split("=")[0]!);
}

describe("canonical env, docker, and route contract", () => {
  it("keeps identical keys and order across all report_service env files", () => {
    const expected = keysFor(".env.dev");
    expect(keysFor(".env.stage")).toEqual(expected);
    expect(keysFor(".env.prod")).toEqual(expected);
    expect(keysFor(".env.example")).toEqual(expected);
  });

  it("does not include forbidden infrastructure enablement gates", () => {
    const keys = keysFor(".env.dev");
    const forbidden = keys.filter((key) => /REPORT_(S3|KAFKA|REDIS|POSTGRES|MONGO|APM|SWAGGER|ELASTICSEARCH)_(ENABLED|REQUIRED)$/i.test(key) || key === "REPORT_MONGO_LOGS_ENABLED");
    expect(forbidden).toEqual([]);
    expect(keys).toContain("REPORT_LOGSTASH_ENABLED");
    expect(text(".env.dev")).toContain("REPORT_LOGSTASH_ENABLED=false");
  });

  it("uses Node 24, exposes 8080, runs non-root, and healthchecks /hello", () => {
    const dockerfile = text("Dockerfile");
    expect(dockerfile).toContain("node:24-bookworm-slim");
    expect(dockerfile).toContain("EXPOSE 8080");
    expect(dockerfile).not.toMatch(/EXPOSE\s+(?!8080)\d+/);
    expect(dockerfile).toContain("USER appuser");
    expect(dockerfile).toContain("/hello");
    expect(dockerfile).not.toMatch(/COPY .*\.env/);
  });

  it("uses the fixed sh command script and host ports 5050/5051/5052", () => {
    const command = text("command.sh");
    expect(command.startsWith("#!/usr/bin/env sh")).toBe(true);
    expect(command).toContain("docker build --no-cache -t report_service:latest .");
    expect(command).toContain("-p 5050:8080");
    expect(command).toContain("-p 5051:8080");
    expect(command).toContain("-p 5052:8080");
    expect(command).not.toContain("curl");
    expect(command).not.toContain("function ");
  });

  it("fixes canonical outbox/inbox DDL and duplicate aggregate_type", () => {
    const migration = text("migrations/001_create_report_schema.sql");
    expect((migration.match(/aggregate_type text not null/g) ?? []).length).toBe(1);
    expect(migration).toContain("create table if not exists report.outbox_events");
    expect(migration).toContain("create table if not exists report.kafka_inbox_events");
    expect(migration).toContain("report_progress_events");
    expect(migration).toContain("checksum_sha256 text not null");
  });

  it("keeps only /docs as public docs and embeds Swagger UI options", () => {
    const app = text("src/http/app.ts");
    const docs = text("src/docs/openapi.ts");
    expect(app).toContain('app.get("/docs"');
    expect(app).not.toContain('app.get("/openapi.json"');
    expect(app).not.toContain('app.get("/v3/api-docs"');
    expect(docs).toContain("persistAuthorization: true");
    expect(docs).toContain("requestInterceptor: (req) =>");
    expect(docs).toContain("SwaggerUIStandalonePreset");
    expect(docs).toContain("StandaloneLayout");
    expect(docs).toContain('const SWAGGER_UI_VERSION = "5.19.0"');
    expect(docs).toContain("swagger-ui-dist@${SWAGGER_UI_VERSION}");
    expect(docs).not.toContain("responses-wrapper");
  });
});
