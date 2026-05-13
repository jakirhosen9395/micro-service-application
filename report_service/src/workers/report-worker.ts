import type { Job, Worker } from "bullmq";
import type { ReportJobData, ReportQueue } from "../queue/report-queue.js";
import type { ReportService } from "../reports/report.service.js";
import type { AppLogger } from "../logging/logger.js";
import { captureApmError, withApmTransaction } from "../observability/apm.js";

function withTimeout<T>(promise: Promise<T>, timeoutMs: number, reportId: string): Promise<T> {
  let timeout: NodeJS.Timeout | undefined;
  const timeoutPromise = new Promise<never>((_, reject) => {
    timeout = setTimeout(() => reject(new Error(`Report generation timed out after ${timeoutMs}ms for ${reportId}`)), timeoutMs);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => {
    if (timeout) clearTimeout(timeout);
  });
}

export function startReportWorker(queue: ReportQueue, reportService: ReportService, logger: AppLogger, timeoutMs: number): Worker<ReportJobData> {
  const worker = queue.createWorker(async (job: Job<ReportJobData>) => {
    logger.info("report generation job started", {
      logger: "app.worker",
      event: "report.job.started",
      request_id: job.data.request_id,
      trace_id: job.data.trace_id,
      correlation_id: job.data.correlation_id,
      extra: { report_id: job.data.report_id, job_id: job.id }
    });
    await withApmTransaction(
      "report_service worker generate-report",
      "worker",
      { report_id: job.data.report_id, request_id: job.data.request_id, trace_id: job.data.trace_id, correlation_id: job.data.correlation_id },
      () => withTimeout(reportService.generateReport(job.data.report_id, job.data), timeoutMs, job.data.report_id)
    );
  });

  worker.on("completed", (job) => {
    logger.info("report generation job completed", {
      logger: "app.worker",
      event: "report.job.completed",
      request_id: job.data.request_id,
      trace_id: job.data.trace_id,
      correlation_id: job.data.correlation_id,
      extra: { report_id: job.data.report_id, job_id: job.id }
    });
  });

  worker.on("failed", (job, error) => {
    captureApmError(error, { report_id: job?.data.report_id, job_id: job?.id ?? null, queue: "report-generation" });
    logger.error("report generation job failed", {
      logger: "app.worker",
      event: "report.job.failed",
      request_id: job?.data.request_id ?? null,
      trace_id: job?.data.trace_id ?? null,
      correlation_id: job?.data.correlation_id ?? null,
      error_code: "REPORT_JOB_FAILED",
      exception_class: error.name,
      exception_message: error.message,
      stack_trace: error.stack ?? null,
      extra: { report_id: job?.data.report_id, job_id: job?.id }
    });
  });

  return worker;
}
