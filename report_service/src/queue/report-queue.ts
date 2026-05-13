import { Queue, Worker, type JobsOptions, type Processor, type QueueEvents } from "bullmq";
import { Redis as IORedis } from "ioredis";
import type { AppConfig } from "../config/config.js";

export interface ReportJobData {
  report_id: string;
  request_id: string;
  trace_id: string;
  correlation_id: string;
}

export class ReportQueue {
  public readonly queue: Queue<ReportJobData>;
  private readonly connection: IORedis;

  public constructor(private readonly config: AppConfig) {
    this.connection = new IORedis({
      host: config.redis.host,
      port: config.redis.port,
      password: config.redis.password,
      db: config.redis.db,
      maxRetriesPerRequest: null
    });
    this.queue = new Queue<ReportJobData>(config.report.bullmqQueueName, {
      connection: this.connection,
      prefix: `${config.service.environment}:${config.service.name}:bullmq`
    });
  }

  public async addReportJob(data: ReportJobData): Promise<void> {
    const options: JobsOptions = {
      jobId: data.report_id,
      removeOnComplete: { age: this.config.report.queueRemoveOnCompleteAgeSeconds },
      removeOnFail: { age: this.config.report.queueRemoveOnFailAgeSeconds },
      attempts: 1
    };
    await this.queue.add("generate-report", data, options);
  }

  public async removeReportJob(reportId: string): Promise<void> {
    const job = await this.queue.getJob(reportId);
    if (!job) return;
    const state = await job.getState();
    if (["waiting", "delayed", "prioritized", "paused"].includes(state)) {
      await job.remove();
    }
  }

  public createWorker(processor: Processor<ReportJobData>): Worker<ReportJobData> {
    return new Worker<ReportJobData>(this.config.report.bullmqQueueName, processor, {
      connection: new IORedis({
        host: this.config.redis.host,
        port: this.config.redis.port,
        password: this.config.redis.password,
        db: this.config.redis.db,
        maxRetriesPerRequest: null
      }),
      concurrency: this.config.report.workerConcurrency,
      prefix: `${this.config.service.environment}:${this.config.service.name}:bullmq`
    });
  }

  public async health(): Promise<void> {
    await this.queue.getJobCounts("waiting", "active", "delayed", "failed");
  }

  public async summary(): Promise<Record<string, number>> {
    return this.queue.getJobCounts("waiting", "active", "delayed", "failed", "completed", "paused", "prioritized");
  }

  public async close(): Promise<void> {
    await this.queue.close();
    await this.connection.quit();
  }
}
