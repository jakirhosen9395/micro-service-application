import { loadEnvFile, normalizeEnvironment, type RuntimeEnvironment } from "./env.js";

loadEnvFile();

export type JwtAlgorithm = "HS256";

function readString(name: string, fallback?: string): string {
  const value = process.env[name];
  if (value === undefined || value === "") {
    if (fallback !== undefined) return fallback;
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function readNumber(name: string, fallback?: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === "") {
    if (fallback !== undefined) return fallback;
    throw new Error(`Missing required environment variable: ${name}`);
  }
  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) throw new Error(`Invalid number for ${name}`);
  return parsed;
}

function readInteger(name: string, fallback?: number): number {
  const value = readNumber(name, fallback);
  if (!Number.isInteger(value)) throw new Error(`Invalid integer for ${name}`);
  return value;
}

function readBoolean(name: string, fallback?: boolean): boolean {
  const raw = process.env[name];
  if (raw === undefined || raw === "") {
    if (fallback !== undefined) return fallback;
    throw new Error(`Missing required environment variable: ${name}`);
  }
  const normalized = raw.trim().toLowerCase();
  if (["1", "true", "yes", "y", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "n", "off"].includes(normalized)) return false;
  throw new Error(`Invalid boolean for ${name}`);
}

function readCsv(name: string, fallback?: string[]): string[] {
  const raw = process.env[name];
  if (raw === undefined || raw === "") {
    if (fallback !== undefined) return fallback;
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return raw.split(",").map((item) => item.trim()).filter(Boolean);
}


const FORBIDDEN_INFRA_TOGGLES = [
  "REPORT_S3_ENABLED",
  "REPORT_KAFKA_ENABLED",
  "REPORT_REDIS_ENABLED",
  "REPORT_POSTGRES_ENABLED",
  "REPORT_MONGO_ENABLED",
  "REPORT_APM_ENABLED",
  "REPORT_SWAGGER_ENABLED",
  "REPORT_S3_REQUIRED",
  "REPORT_KAFKA_REQUIRED",
  "REPORT_REDIS_REQUIRED",
  "REPORT_POSTGRES_REQUIRED",
  "REPORT_MONGO_REQUIRED",
  "REPORT_MONGO_LOGS_ENABLED",
  "REPORT_APM_REQUIRED",
  "REPORT_ELASTICSEARCH_REQUIRED"
] as const;

function rejectForbiddenInfraToggles(): void {
  const present = FORBIDDEN_INFRA_TOGGLES.filter((key) => Object.prototype.hasOwnProperty.call(process.env, key));
  if (present.length > 0) throw new Error(`Forbidden infrastructure toggle(s): ${present.join(", ")}`);
}

export interface AppConfig {
  service: {
    name: "report_service";
    environment: RuntimeEnvironment;
    nodeEnv: RuntimeEnvironment;
    version: string;
    tenant: string;
    host: string;
    port: number;
  };
  jwt: {
    secret: string;
    issuer: string;
    audience: string;
    algorithm: JwtAlgorithm;
    leewaySeconds: number;
  };
  postgres: {
    host: string;
    port: number;
    user: string;
    password: string;
    database: string;
    schema: "report";
    poolSize: number;
    maxOverflow: number;
    migrationMode: "auto" | "manual";
  };
  redis: {
    host: string;
    port: number;
    password: string;
    db: number;
    cacheTtlSeconds: number;
  };
  kafka: {
    bootstrapServers: string[];
    eventsTopic: string;
    deadLetterTopic: string;
    consumerGroup: string;
    consumeTopics: string[];
    autoCreateTopics: boolean;
  };
  s3: {
    endpoint: string;
    accessKey: string;
    secretKey: string;
    region: string;
    forcePathStyle: boolean;
    bucket: "microservice";
    auditPrefix: string;
    reportPrefix: string;
  };
  mongo: {
    host: string;
    port: number;
    username: string;
    password: string;
    database: string;
    authSource: string;
    logCollection: string;
  };
  apm: {
    serverUrl: string;
    secretToken: string;
    transactionSampleRate: number;
    captureBody: "off" | "errors" | "transactions" | "all";
  };
  elasticsearch: {
    url: string;
    username: string;
    password: string;
  };
  kibana: {
    url: string;
    username: string;
    password: string;
  };
  logging: {
    level: "trace" | "debug" | "info" | "warn" | "error";
    format: "pretty-json";
    logstashEnabled: boolean;
    logstashHost: string;
    logstashPort: number;
  };
  cors: {
    allowedOrigins: string[];
    allowedMethods: string[];
    allowedHeaders: string[];
    allowCredentials: boolean;
    maxAgeSeconds: number;
  };
  security: {
    requireHttps: boolean;
    secureCookies: boolean;
    requireTenantMatch: boolean;
  };
  report: {
    bullmqQueueName: string;
    workerConcurrency: number;
    queueRemoveOnCompleteAgeSeconds: number;
    queueRemoveOnFailAgeSeconds: number;
    queueJobTimeoutMs: number;
    generationMaxRows: number;
    previewMaxBytes: number;
    downloadContentDisposition: "attachment" | "inline";
    workerShutdownGraceMs: number;
  };
}

let cached: AppConfig | undefined;

export function loadConfig(): AppConfig {
  if (cached) return cached;
  rejectForbiddenInfraToggles();

  const environment = normalizeEnvironment(readString("REPORT_ENV", "development"));
  const nodeEnv = normalizeEnvironment(readString("REPORT_NODE_ENV", environment));
  const serviceName = readString("REPORT_SERVICE_NAME");
  const port = readInteger("REPORT_PORT");
  const algorithm = readString("REPORT_JWT_ALGORITHM") as JwtAlgorithm;
  const schema = readString("REPORT_POSTGRES_SCHEMA") as "report";
  const migrationMode = readString("REPORT_POSTGRES_MIGRATION_MODE") as "auto" | "manual";
  const bucket = readString("REPORT_S3_BUCKET") as "microservice";
  const logFormat = readString("REPORT_LOG_FORMAT") as "pretty-json";
  const level = readString("REPORT_LOG_LEVEL", "info") as AppConfig["logging"]["level"];
  const captureBody = readString("REPORT_APM_CAPTURE_BODY", "errors") as AppConfig["apm"]["captureBody"];
  const contentDisposition = readString("REPORT_DOWNLOAD_CONTENT_DISPOSITION", "attachment") as "attachment" | "inline";

  if (serviceName !== "report_service") throw new Error("REPORT_SERVICE_NAME must be report_service");
  if (port !== 8080) throw new Error("REPORT_PORT must be 8080");
  if (algorithm !== "HS256") throw new Error("REPORT_JWT_ALGORITHM must be HS256");
  if (schema !== "report") throw new Error("REPORT_POSTGRES_SCHEMA must be report");
  if (!["auto", "manual"].includes(migrationMode)) throw new Error("REPORT_POSTGRES_MIGRATION_MODE must be auto or manual");
  if (bucket !== "microservice") throw new Error("REPORT_S3_BUCKET must be microservice");
  if (logFormat !== "pretty-json") throw new Error("REPORT_LOG_FORMAT must be pretty-json");
  if (!["trace", "debug", "info", "warn", "error"].includes(level)) throw new Error("Invalid REPORT_LOG_LEVEL");
  if (!["off", "errors", "transactions", "all"].includes(captureBody)) throw new Error("Invalid REPORT_APM_CAPTURE_BODY");
  if (!["attachment", "inline"].includes(contentDisposition)) throw new Error("REPORT_DOWNLOAD_CONTENT_DISPOSITION must be attachment or inline");
  if (readBoolean("REPORT_LOGSTASH_ENABLED") !== false) throw new Error("REPORT_LOGSTASH_ENABLED must be false");

  cached = {
    service: {
      name: "report_service",
      environment,
      nodeEnv,
      version: readString("REPORT_VERSION"),
      tenant: readString("REPORT_TENANT"),
      host: readString("REPORT_HOST"),
      port
    },
    jwt: {
      secret: readString("REPORT_JWT_SECRET"),
      issuer: readString("REPORT_JWT_ISSUER"),
      audience: readString("REPORT_JWT_AUDIENCE"),
      algorithm,
      leewaySeconds: readInteger("REPORT_JWT_LEEWAY_SECONDS")
    },
    postgres: {
      host: readString("REPORT_POSTGRES_HOST"),
      port: readInteger("REPORT_POSTGRES_PORT"),
      user: readString("REPORT_POSTGRES_USER"),
      password: readString("REPORT_POSTGRES_PASSWORD"),
      database: readString("REPORT_POSTGRES_DB"),
      schema,
      poolSize: readInteger("REPORT_POSTGRES_POOL_SIZE"),
      maxOverflow: readInteger("REPORT_POSTGRES_MAX_OVERFLOW"),
      migrationMode
    },
    redis: {
      host: readString("REPORT_REDIS_HOST"),
      port: readInteger("REPORT_REDIS_PORT"),
      password: readString("REPORT_REDIS_PASSWORD"),
      db: readInteger("REPORT_REDIS_DB"),
      cacheTtlSeconds: readInteger("REPORT_REDIS_CACHE_TTL_SECONDS")
    },
    kafka: {
      bootstrapServers: readCsv("REPORT_KAFKA_BOOTSTRAP_SERVERS"),
      eventsTopic: readString("REPORT_KAFKA_EVENTS_TOPIC"),
      deadLetterTopic: readString("REPORT_KAFKA_DEAD_LETTER_TOPIC"),
      consumerGroup: readString("REPORT_KAFKA_CONSUMER_GROUP"),
      consumeTopics: readCsv("REPORT_KAFKA_CONSUME_TOPICS"),
      autoCreateTopics: readBoolean("REPORT_KAFKA_AUTO_CREATE_TOPICS")
    },
    s3: {
      endpoint: readString("REPORT_S3_ENDPOINT"),
      accessKey: readString("REPORT_S3_ACCESS_KEY"),
      secretKey: readString("REPORT_S3_SECRET_KEY"),
      region: readString("REPORT_S3_REGION"),
      forcePathStyle: readBoolean("REPORT_S3_FORCE_PATH_STYLE"),
      bucket,
      auditPrefix: readString("REPORT_S3_AUDIT_PREFIX"),
      reportPrefix: readString("REPORT_S3_REPORT_PREFIX")
    },
    mongo: {
      host: readString("REPORT_MONGO_HOST"),
      port: readInteger("REPORT_MONGO_PORT"),
      username: readString("REPORT_MONGO_USERNAME"),
      password: readString("REPORT_MONGO_PASSWORD"),
      database: readString("REPORT_MONGO_DATABASE"),
      authSource: readString("REPORT_MONGO_AUTH_SOURCE"),
      logCollection: readString("REPORT_MONGO_LOG_COLLECTION")
    },
    apm: {
      serverUrl: readString("REPORT_APM_SERVER_URL"),
      secretToken: readString("REPORT_APM_SECRET_TOKEN"),
      transactionSampleRate: readNumber("REPORT_APM_TRANSACTION_SAMPLE_RATE"),
      captureBody
    },
    elasticsearch: {
      url: readString("REPORT_ELASTICSEARCH_URL"),
      username: readString("REPORT_ELASTICSEARCH_USERNAME"),
      password: readString("REPORT_ELASTICSEARCH_PASSWORD")
    },
    kibana: {
      url: readString("REPORT_KIBANA_URL"),
      username: readString("REPORT_KIBANA_USERNAME"),
      password: readString("REPORT_KIBANA_PASSWORD")
    },
    logging: {
      level,
      format: logFormat,
      logstashEnabled: readBoolean("REPORT_LOGSTASH_ENABLED"),
      logstashHost: readString("REPORT_LOGSTASH_HOST"),
      logstashPort: readInteger("REPORT_LOGSTASH_PORT")
    },
    cors: {
      allowedOrigins: readCsv("REPORT_CORS_ALLOWED_ORIGINS"),
      allowedMethods: readCsv("REPORT_CORS_ALLOWED_METHODS"),
      allowedHeaders: readCsv("REPORT_CORS_ALLOWED_HEADERS"),
      allowCredentials: readBoolean("REPORT_CORS_ALLOW_CREDENTIALS"),
      maxAgeSeconds: readInteger("REPORT_CORS_MAX_AGE_SECONDS")
    },
    security: {
      requireHttps: readBoolean("REPORT_SECURITY_REQUIRE_HTTPS"),
      secureCookies: readBoolean("REPORT_SECURITY_SECURE_COOKIES"),
      requireTenantMatch: readBoolean("REPORT_SECURITY_REQUIRE_TENANT_MATCH")
    },
    report: {
      bullmqQueueName: readString("REPORT_BULLMQ_QUEUE_NAME"),
      workerConcurrency: readInteger("REPORT_WORKER_CONCURRENCY"),
      queueRemoveOnCompleteAgeSeconds: readInteger("REPORT_QUEUE_REMOVE_ON_COMPLETE_AGE_SECONDS"),
      queueRemoveOnFailAgeSeconds: readInteger("REPORT_QUEUE_REMOVE_ON_FAIL_AGE_SECONDS"),
      queueJobTimeoutMs: readInteger("REPORT_QUEUE_JOB_TIMEOUT_MS"),
      generationMaxRows: readInteger("REPORT_GENERATION_MAX_ROWS"),
      previewMaxBytes: readInteger("REPORT_PREVIEW_MAX_BYTES"),
      downloadContentDisposition: contentDisposition,
      workerShutdownGraceMs: readInteger("REPORT_WORKER_SHUTDOWN_GRACE_MS")
    }
  };

  return cached;
}
