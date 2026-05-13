import type { AppConfig } from "../config/config.js";
import { checkApmServer, checkElasticsearch, withApmSpan } from "../observability/apm.js";
import type { PostgresDatabase } from "../persistence/postgres.js";
import type { RedisCache } from "../cache/redis.js";
import type { KafkaBus } from "../kafka/kafka.js";
import type { S3Storage } from "../storage/s3.js";
import type { MongoLogWriter } from "../logging/mongo-log-writer.js";

export interface DependencyHealth {
  status: "ok" | "down";
  latency_ms: number;
  error_code?: string;
}

export interface HealthResponse {
  status: "ok" | "down";
  service: string;
  version: string;
  environment: string;
  timestamp: string;
  dependencies: {
    jwt: DependencyHealth;
    postgres: DependencyHealth;
    redis: DependencyHealth;
    kafka: DependencyHealth;
    s3: DependencyHealth;
    mongodb: DependencyHealth;
    apm: DependencyHealth;
    elasticsearch: DependencyHealth;
  };
}

export interface HealthDependencies {
  postgres: PostgresDatabase;
  redis: RedisCache;
  kafka: KafkaBus;
  s3: S3Storage;
  mongodb: MongoLogWriter;
}

async function measure(errorCode: string, check: () => Promise<void>): Promise<DependencyHealth> {
  const start = performance.now();
  try {
    await withApmSpan(`health.${errorCode.toLowerCase()}`, "app", "health", "check", check);
    return { status: "ok", latency_ms: Number((performance.now() - start).toFixed(1)) };
  } catch {
    return { status: "down", latency_ms: Number((performance.now() - start).toFixed(1)), error_code: errorCode };
  }
}

export async function buildHealthResponse(config: AppConfig, deps: HealthDependencies): Promise<HealthResponse> {
  const dependencies = {
    jwt: await measure("JWT_CONFIG_INVALID", async () => {
      if (!config.jwt.secret || config.jwt.algorithm !== "HS256") throw new Error("JWT config invalid");
    }),
    postgres: await measure("POSTGRES_UNAVAILABLE", () => deps.postgres.health()),
    redis: await measure("REDIS_UNAVAILABLE", () => deps.redis.health()),
    kafka: await measure("KAFKA_UNAVAILABLE", () => deps.kafka.health()),
    s3: await measure("S3_UNAVAILABLE", () => deps.s3.health()),
    mongodb: await measure("MONGODB_UNAVAILABLE", () => deps.mongodb.health()),
    apm: await measure("APM_UNAVAILABLE", () => checkApmServer(config)),
    elasticsearch: await measure("ELASTICSEARCH_UNAVAILABLE", () => checkElasticsearch(config))
  };
  const status = Object.values(dependencies).every((item) => item.status === "ok") ? "ok" : "down";
  return {
    status,
    service: config.service.name,
    version: config.service.version,
    environment: config.service.environment,
    timestamp: new Date().toISOString(),
    dependencies
  };
}
