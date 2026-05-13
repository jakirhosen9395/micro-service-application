import os from "node:os";
import apm, { type Agent, type Span, type Transaction } from "elastic-apm-node";
import type { AppConfig } from "../config/config.js";

export type ApmLabelValue = string | number | boolean | null | undefined;
export type ApmLabels = Record<string, ApmLabelValue>;
export type ApmTransaction = Transaction;

type ElasticAgentWithRuntimeState = Agent & {
  isStarted?: () => boolean;
  setTransactionName?: (name: string) => void;
  currentTraceIds?: Record<string, string>;
};

type NamedTransaction = Transaction & {
  name?: string;
};

export function startApm(config: AppConfig): Agent {
  const agent = apm as ElasticAgentWithRuntimeState;
  if (process.env.REPORT_APM_PRELOADED === "1" || agent.isStarted?.()) return apm;

  return apm.start({
    serviceName: config.service.name,
    serviceVersion: config.service.version.replace(/^v/i, ""),
    serviceNodeName: os.hostname(),
    serverUrl: config.apm.serverUrl,
    secretToken: config.apm.secretToken,
    environment: config.service.environment,
    active: true,
    transactionSampleRate: config.apm.transactionSampleRate,
    captureBody: config.apm.captureBody,
    captureHeaders: true,
    centralConfig: true,
    breakdownMetrics: true,
    metricsInterval: "30s",
    captureExceptions: true,
    globalLabels: {
      tenant: config.service.tenant,
      service: config.service.name
    }
  });
}

export function currentTransaction(): Transaction | null {
  return apm.currentTransaction ?? null;
}

export function setApmTransactionName(name: string): void {
  const agent = apm as ElasticAgentWithRuntimeState;
  if (typeof agent.setTransactionName === "function") {
    agent.setTransactionName(name);
    return;
  }

  const transaction = apm.currentTransaction as NamedTransaction | null;
  setTransactionName(transaction, name);
}

export function setApmOutcome(outcome: "success" | "failure" | "unknown"): void {
  apm.currentTransaction?.setOutcome(outcome);
}

export function setApmLabels(labels: ApmLabels): void {
  const transaction = apm.currentTransaction;
  if (!transaction) return;
  for (const [key, value] of Object.entries(labels)) {
    if (value !== null && value !== undefined) transaction.setLabel(key, value);
  }
}

export function startApmHttpTransaction(name: string, labels: ApmLabels = {}): Transaction | null {
  if (apm.currentTransaction) return null;
  const transaction = apm.startTransaction(name, "request") ?? null;
  if (!transaction) return null;
  setTransactionLabels(transaction, labels);
  return transaction;
}

export function finishApmHttpTransaction(
  transaction: Transaction | null | undefined,
  name: string,
  outcome: "success" | "failure" | "unknown",
  labels: ApmLabels = {}
): void {
  if (!transaction) return;
  setTransactionName(transaction, name);
  setTransactionLabels(transaction, labels);
  transaction.setOutcome(outcome);
  transaction.end();
}

export function captureApmError(error: unknown, labels: ApmLabels = {}): void {
  if (!shouldCaptureApmError(error)) return;

  if (error instanceof Error) {
    apm.captureError(error, { labels: sanitizeLabels(labels) });
  } else {
    apm.captureError(String(error), { labels: sanitizeLabels(labels) });
  }
}

export async function withApmSpan<T>(
  name: string,
  type: string,
  subtype: string,
  action: string,
  operation: () => Promise<T>,
  labels: ApmLabels = {}
): Promise<T> {
  const span: Span | null = apm.startSpan(name, type, subtype, action) ?? null;
  try {
    for (const [key, value] of Object.entries(sanitizeLabels(labels))) span?.setLabel(key, value);
    const result = await operation();
    span?.setOutcome("success");
    return result;
  } catch (error) {
    span?.setOutcome(shouldCaptureApmError(error) ? "failure" : "success");
    captureApmError(error, { span: name, dependency: subtype });
    throw error;
  } finally {
    span?.end();
  }
}

export async function withApmTransaction<T>(name: string, type: string, labels: ApmLabels, operation: () => Promise<T>): Promise<T> {
  const transaction = apm.startTransaction(name, type);
  try {
    for (const [key, value] of Object.entries(sanitizeLabels(labels))) transaction?.setLabel(key, value);
    const result = await operation();
    transaction?.setOutcome("success");
    return result;
  } catch (error) {
    transaction?.setOutcome(shouldCaptureApmError(error) ? "failure" : "success");
    captureApmError(error, labels);
    throw error;
  } finally {
    transaction?.end();
  }
}

export function getApmTraceContext(): { traceId: string | null; transactionId: string | null; spanId: string | null; ecs: Record<string, string> } {
  const ids = (apm as ElasticAgentWithRuntimeState).currentTraceIds ?? {};
  return {
    traceId: ids["trace.id"] ?? null,
    transactionId: ids["transaction.id"] ?? null,
    spanId: ids["span.id"] ?? null,
    ecs: ids
  };
}

function shouldCaptureApmError(error: unknown): boolean {
  const statusCode = statusCodeFromError(error);
  return statusCode === undefined || statusCode >= 500;
}

function statusCodeFromError(error: unknown): number | undefined {
  if (!error || typeof error !== "object") return undefined;
  const statusCode = (error as { statusCode?: unknown }).statusCode;
  return typeof statusCode === "number" && Number.isInteger(statusCode) ? statusCode : undefined;
}

function setTransactionName(transaction: Transaction | null | undefined, name: string): void {
  if (!transaction) return;
  (transaction as NamedTransaction).name = name;
}

function setTransactionLabels(transaction: Transaction | null | undefined, labels: ApmLabels): void {
  if (!transaction) return;
  for (const [key, value] of Object.entries(sanitizeLabels(labels))) {
    transaction.setLabel(key, value);
  }
}

function sanitizeLabels(labels: ApmLabels): Record<string, string | number | boolean> {
  const sanitized: Record<string, string | number | boolean> = {};
  for (const [key, value] of Object.entries(labels)) {
    if (value !== null && value !== undefined) sanitized[key] = value;
  }
  return sanitized;
}

export async function checkApmServer(config: AppConfig): Promise<void> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 3000);
  try {
    const response = await fetch(config.apm.serverUrl, { method: "GET", signal: controller.signal });
    if (![200, 401, 403, 404].includes(response.status)) {
      throw new Error(`APM server returned HTTP ${response.status}`);
    }
  } finally {
    clearTimeout(timeout);
  }
}

export async function checkElasticsearch(config: AppConfig): Promise<void> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 3000);
  try {
    const basic = Buffer.from(`${config.elasticsearch.username}:${config.elasticsearch.password}`).toString("base64");
    const response = await fetch(config.elasticsearch.url, {
      method: "GET",
      headers: { Authorization: `Basic ${basic}` },
      signal: controller.signal
    });
    if (!response.ok) throw new Error(`Elasticsearch returned HTTP ${response.status}`);
  } finally {
    clearTimeout(timeout);
  }
}
