import os from "node:os";
import type { AppConfig } from "../config/config.js";
import { getApmTraceContext } from "../observability/apm.js";
import { redactSecrets } from "./redaction.js";

export type LogLevel = "TRACE" | "DEBUG" | "INFO" | "WARN" | "ERROR";

const LEVEL_ORDER: Record<Lowercase<LogLevel>, number> = {
  trace: 10,
  debug: 20,
  info: 30,
  warn: 40,
  error: 50
};

export interface CanonicalLogDocument {
  timestamp: string;
  level: LogLevel;
  service: string;
  version: string;
  environment: string;
  tenant: string;
  logger: string;
  event: string;
  message: string;
  request_id: string | null;
  trace_id: string | null;
  correlation_id: string | null;
  elastic_trace_id: string | null;
  elastic_transaction_id: string | null;
  elastic_span_id: string | null;
  user_id: string | null;
  actor_id: string | null;
  method: string | null;
  path: string | null;
  status_code: number | null;
  duration_ms: number | null;
  client_ip: string | null;
  user_agent: string | null;
  dependency: string | null;
  error_code: string | null;
  exception_class: string | null;
  exception_message: string | null;
  stack_trace: string | null;
  host: string;
  extra: Record<string, unknown>;
}

export interface MongoLogWriterLike {
  insert(document: CanonicalLogDocument): Promise<void>;
}

export interface LogFields {
  logger?: string;
  event?: string;
  request_id?: string | null;
  trace_id?: string | null;
  correlation_id?: string | null;
  user_id?: string | null;
  actor_id?: string | null;
  method?: string | null;
  path?: string | null;
  status_code?: number | null;
  duration_ms?: number | null;
  client_ip?: string | null;
  user_agent?: string | null;
  dependency?: string | null;
  error_code?: string | null;
  exception_class?: string | null;
  exception_message?: string | null;
  stack_trace?: string | null;
  extra?: Record<string, unknown>;
}

export class AppLogger {
  private mongoWriter?: MongoLogWriterLike;
  private readonly threshold: number;

  public constructor(private readonly config: AppConfig) {
    this.threshold = LEVEL_ORDER[config.logging.level] ?? LEVEL_ORDER.info;
  }

  public setMongoWriter(writer: MongoLogWriterLike): void {
    this.mongoWriter = writer;
  }

  public trace(message: string, fields: LogFields = {}): void {
    this.write("TRACE", message, fields);
  }

  public debug(message: string, fields: LogFields = {}): void {
    this.write("DEBUG", message, fields);
  }

  public info(message: string, fields: LogFields = {}): void {
    this.write("INFO", message, fields);
  }

  public warn(message: string, fields: LogFields = {}): void {
    this.write("WARN", message, fields);
  }

  public error(message: string, fields: LogFields = {}): void {
    this.write("ERROR", message, fields);
  }

  private shouldWrite(level: LogLevel): boolean {
    return LEVEL_ORDER[level.toLowerCase() as Lowercase<LogLevel>] >= this.threshold;
  }

  private write(level: LogLevel, message: string, fields: LogFields): void {
    if (!this.shouldWrite(level)) return;

    const apmContext = getApmTraceContext();
    const document: CanonicalLogDocument = redactSecrets({
      timestamp: new Date().toISOString(),
      level,
      service: this.config.service.name,
      version: this.config.service.version,
      environment: this.config.service.environment,
      tenant: this.config.service.tenant,
      logger: fields.logger ?? "app",
      event: fields.event ?? "application.log",
      message,
      request_id: fields.request_id ?? null,
      trace_id: fields.trace_id ?? null,
      correlation_id: fields.correlation_id ?? null,
      elastic_trace_id: apmContext.traceId,
      elastic_transaction_id: apmContext.transactionId,
      elastic_span_id: apmContext.spanId,
      user_id: fields.user_id ?? null,
      actor_id: fields.actor_id ?? null,
      method: fields.method ?? null,
      path: fields.path ?? null,
      status_code: fields.status_code ?? null,
      duration_ms: fields.duration_ms ?? null,
      client_ip: fields.client_ip ?? null,
      user_agent: fields.user_agent ?? null,
      dependency: fields.dependency ?? null,
      error_code: fields.error_code ?? null,
      exception_class: fields.exception_class ?? null,
      exception_message: fields.exception_message ?? null,
      stack_trace: fields.stack_trace ?? null,
      host: os.hostname(),
      extra: fields.extra ?? {}
    });

    const stdoutDocument = {
      ...document,
      "service.name": document.service,
      "service.version": document.version,
      "service.environment": document.environment,
      "service.node.name": document.host,
      "event.dataset": `${document.service}.${document.logger}`,
      "trace.id": apmContext.traceId,
      "transaction.id": apmContext.transactionId,
      "span.id": apmContext.spanId
    };

    process.stdout.write(`${JSON.stringify(stdoutDocument, null, 2)}\n`);

    if (this.mongoWriter) {
      this.mongoWriter.insert(document).catch((error: unknown) => {
        const fallback = redactSecrets({
          timestamp: new Date().toISOString(),
          level: "ERROR",
          service: this.config.service.name,
          version: this.config.service.version,
          environment: this.config.service.environment,
          tenant: this.config.service.tenant,
          logger: "app.logging",
          event: "mongodb.log_write_failed",
          message: "MongoDB structured log write failed",
          request_id: document.request_id,
          trace_id: document.trace_id,
          correlation_id: document.correlation_id,
          elastic_trace_id: document.elastic_trace_id,
          elastic_transaction_id: document.elastic_transaction_id,
          elastic_span_id: document.elastic_span_id,
          user_id: document.user_id,
          actor_id: document.actor_id,
          method: document.method,
          path: document.path,
          status_code: document.status_code,
          duration_ms: document.duration_ms,
          client_ip: document.client_ip,
          user_agent: document.user_agent,
          dependency: "mongodb",
          error_code: "MONGO_LOG_WRITE_FAILED",
          exception_class: error instanceof Error ? error.name : "Error",
          exception_message: error instanceof Error ? error.message : String(error),
          stack_trace: null,
          host: os.hostname(),
          extra: {}
        });
        process.stderr.write(`${JSON.stringify({
          ...fallback,
          "service.name": fallback.service,
          "service.version": fallback.version,
          "service.environment": fallback.environment,
          "service.node.name": fallback.host,
          "event.dataset": `${fallback.service}.${fallback.logger}`,
          "trace.id": fallback.elastic_trace_id,
          "transaction.id": fallback.elastic_transaction_id,
          "span.id": fallback.elastic_span_id
        }, null, 2)}\n`);
      });
    }
  }
}

export function shouldSuppressSuccessfulRequestLog(path: string, statusCode: number): boolean {
  return statusCode >= 200 && statusCode < 400 && ["/hello", "/health", "/docs"].includes(path);
}
