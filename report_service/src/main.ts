import type { Worker } from "bullmq";
import { loadConfig } from "./config/config.js";
import { AppLogger } from "./logging/logger.js";
import { MongoLogWriter } from "./logging/mongo-log-writer.js";
import { startApm } from "./observability/apm.js";
import { PostgresDatabase } from "./persistence/postgres.js";
import { RedisCache } from "./cache/redis.js";
import { KafkaBus } from "./kafka/kafka.js";
import { ReportQueue } from "./queue/report-queue.js";
import { S3Storage } from "./storage/s3.js";
import { AuditService } from "./storage/audit-service.js";
import { ReportService } from "./reports/report.service.js";
import { buildApp } from "./http/app.js";
import { OutboxPublisher } from "./persistence/outbox.js";
import { ProjectionService } from "./projections/projection-service.js";
import { startReportWorker } from "./workers/report-worker.js";

const MODES = ["api", "all", "worker", "consumer", "outbox", "scheduler"] as const;
type Mode = (typeof MODES)[number];

function modeFromArg(value: string | undefined): Mode {
  if (value && MODES.includes(value as Mode)) return value as Mode;
  return "api";
}

async function bootstrap() {
  const config = loadConfig();
  const logger = new AppLogger(config);
  startApm(config);

  logger.info("application bootstrap starting", {
    logger: "app.startup",
    event: "application.bootstrap_started",
    extra: { mode: modeFromArg(process.argv[2]), service: config.service.name, environment: config.service.environment, version: config.service.version }
  });

  const db = new PostgresDatabase(config, logger);
  await db.connect();
  await db.runMigrations();

  const redis = new RedisCache(config);
  await redis.connect();

  const kafka = new KafkaBus(config, logger);
  await kafka.connectProducerAndAdmin();

  const s3 = new S3Storage(config);
  await s3.health();

  const mongo = new MongoLogWriter(config, logger);
  await mongo.connect();
  logger.setMongoWriter(mongo);

  const queue = new ReportQueue(config);
  await queue.health();

  const audit = new AuditService(config, db, s3, logger);
  const reportService = new ReportService(config, db, queue, redis, s3, audit, logger);
  const outboxPublisher = new OutboxPublisher(db, kafka, config, logger);
  const projectionService = new ProjectionService(db, kafka, logger);

  const runtime = {
    config,
    logger,
    reportService,
    healthDependencies: { postgres: db, redis, kafka, s3, mongodb: mongo },
    s3
  };

  const resources = { db, redis, kafka, mongo, queue, outboxPublisher };
  return { config, logger, reportService, projectionService, outboxPublisher, runtime, resources };
}

async function main(): Promise<void> {
  const mode = modeFromArg(process.argv[2]);
  const boot = await bootstrap();
  const workers: Worker[] = [];

  const shutdown = async (signal: string) => {
    boot.logger.info("application shutdown starting", { logger: "app.shutdown", event: "application.shutdown_started", extra: { signal } });
    boot.resources.outboxPublisher.stop();
    await Promise.allSettled(workers.map((worker) => worker.close()));
    await Promise.allSettled([
      boot.resources.queue.close(),
      boot.resources.kafka.close(),
      boot.resources.redis.close(),
      boot.resources.mongo.close(),
      boot.resources.db.close()
    ]);
    boot.logger.info("application shutdown completed", { logger: "app.shutdown", event: "application.shutdown_completed", extra: { signal } });
    process.exit(0);
  };

  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("SIGTERM", () => void shutdown("SIGTERM"));

  if (mode === "api" || mode === "all") {
    boot.resources.outboxPublisher.start();
    void boot.projectionService.start();
    workers.push(startReportWorker(boot.resources.queue, boot.reportService, boot.logger, boot.config.report.queueJobTimeoutMs));
    const app = buildApp(boot.runtime);
    await app.listen({ host: boot.config.service.host, port: boot.config.service.port });
    boot.logger.info("application started", {
      logger: "app.startup",
      event: "application.started",
      extra: { mode, host: boot.config.service.host, port: boot.config.service.port }
    });
    return;
  }

  if (mode === "worker") {
    workers.push(startReportWorker(boot.resources.queue, boot.reportService, boot.logger, boot.config.report.queueJobTimeoutMs));
    boot.logger.info("report worker started", { logger: "app.startup", event: "worker.started" });
    await new Promise<never>(() => undefined);
  }

  if (mode === "consumer") {
    await boot.projectionService.start();
    boot.logger.info("Kafka consumer started", { logger: "app.startup", event: "consumer.started" });
    await new Promise<never>(() => undefined);
  }

  if (mode === "outbox") {
    await boot.outboxPublisher.runForever();
  }

  if (mode === "scheduler") {
    boot.logger.info("scheduler mode started", { logger: "app.scheduler", event: "scheduler.started" });
    await new Promise<never>(() => undefined);
  }
}

main().catch((error: unknown) => {
  try {
    const config = loadConfig();
    const logger = new AppLogger(config);
    logger.error("application startup failed", {
      logger: "app.startup",
      event: "application.startup_failed",
      exception_class: error instanceof Error ? error.name : "Error",
      exception_message: error instanceof Error ? error.message : String(error),
      stack_trace: error instanceof Error ? error.stack ?? null : null
    });
  } catch {
    process.stderr.write(`${JSON.stringify({
      timestamp: new Date().toISOString(),
      level: "ERROR",
      service: "report_service",
      version: "unknown",
      environment: "unknown",
      tenant: "unknown",
      logger: "app.startup",
      event: "application.startup_failed",
      message: "application startup failed before configuration loaded",
      request_id: null,
      trace_id: null,
      correlation_id: null,
      user_id: null,
      actor_id: null,
      method: null,
      path: null,
      status_code: null,
      duration_ms: null,
      client_ip: null,
      user_agent: null,
      dependency: null,
      error_code: "CONFIG_LOAD_FAILED",
      exception_class: error instanceof Error ? error.name : "Error",
      exception_message: error instanceof Error ? error.message : String(error),
      stack_trace: null,
      host: "unknown",
      extra: {}
    }, null, 2)}\n`);
  }
  process.exit(1);
});
