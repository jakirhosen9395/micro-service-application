const { existsSync } = require("node:fs");
const os = require("node:os");
const { resolve } = require("node:path");
const dotenv = require("dotenv");

function normalizeEnvironment(value, fallback = "development") {
  const raw = String(value || "").trim().toLowerCase();
  if (raw === "dev" || raw === "development") return "development";
  if (raw === "stage" || raw === "staging") return "stage";
  if (raw === "prod" || raw === "production") return "production";
  return fallback;
}

function envFileSuffix(environment) {
  if (environment === "development") return "dev";
  if (environment === "stage") return "stage";
  return "prod";
}

function loadEnvFile() {
  const explicit = process.env.REPORT_ENV_FILE || process.env.ENV_FILE;
  const candidates = [];
  if (explicit) candidates.push(explicit);

  const requested = normalizeEnvironment(process.env.REPORT_ENV || process.env.REPORT_NODE_ENV || process.env.NODE_ENV);
  candidates.push(`.env.${envFileSuffix(requested)}`);
  candidates.push(".env.dev");

  for (const candidate of candidates) {
    const fullPath = resolve(process.cwd(), candidate);
    if (existsSync(fullPath)) {
      dotenv.config({ path: fullPath, override: false });
      return;
    }
  }
}

function numberValue(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function labels(input) {
  return Object.fromEntries(Object.entries(input).filter(([, value]) => value !== undefined && value !== null && value !== ""));
}

loadEnvFile();

const serverUrl = process.env.REPORT_APM_SERVER_URL || process.env.ELASTIC_APM_SERVER_URL;

if (serverUrl) {
  const apm = require("elastic-apm-node");
  const serviceName = process.env.REPORT_SERVICE_NAME || process.env.ELASTIC_APM_SERVICE_NAME || "report_service";
  const serviceVersion = (process.env.REPORT_VERSION || process.env.ELASTIC_APM_SERVICE_VERSION || "0.0.0").replace(/^v/i, "");
  const environment = normalizeEnvironment(process.env.REPORT_ENV || process.env.REPORT_NODE_ENV || process.env.NODE_ENV);

  apm.start({
    serviceName,
    serviceVersion,
    serviceNodeName: os.hostname(),
    serverUrl,
    secretToken: process.env.REPORT_APM_SECRET_TOKEN || process.env.ELASTIC_APM_SECRET_TOKEN,
    environment,
    active: true,
    transactionSampleRate: numberValue(process.env.REPORT_APM_TRANSACTION_SAMPLE_RATE || process.env.ELASTIC_APM_TRANSACTION_SAMPLE_RATE, 1),
    captureBody: process.env.REPORT_APM_CAPTURE_BODY || process.env.ELASTIC_APM_CAPTURE_BODY || "errors",
    captureHeaders: true,
    captureExceptions: true,
    centralConfig: true,
    breakdownMetrics: true,
    metricsInterval: "30s",
    globalLabels: labels({
      tenant: process.env.REPORT_TENANT,
      service: serviceName
    })
  });
  process.env.REPORT_APM_PRELOADED = "1";
}
