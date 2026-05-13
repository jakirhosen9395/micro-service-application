import { randomUUID } from "node:crypto";
import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from "fastify";
import type { AppConfig } from "../config/config.js";
import { buildOpenApiDocument, renderSwaggerHtml } from "../docs/openapi.js";
import { errorEnvelope, success } from "./envelope.js";
import { Errors, isAppError } from "./errors.js";
import { ZodError } from "zod";
import { authenticateRequest } from "../security/jwt.js";
import type { AppLogger } from "../logging/logger.js";
import { shouldSuppressSuccessfulRequestLog } from "../logging/logger.js";
import type { ReportService } from "../reports/report.service.js";
import { createReportRequestSchema, createScheduleSchema, createTemplateSchema, listReportsQuerySchema, updateScheduleSchema, updateTemplateSchema } from "../reports/report-schemas.js";
import type { HealthDependencies } from "./health.js";
import { buildHealthResponse } from "./health.js";
import type { S3Storage } from "../storage/s3.js";
import { captureApmError, finishApmHttpTransaction, setApmLabels, setApmOutcome, setApmTransactionName, startApmHttpTransaction, type ApmTransaction } from "../observability/apm.js";

export interface AppRuntime {
  config: AppConfig;
  logger: AppLogger;
  reportService: ReportService;
  healthDependencies: HealthDependencies;
  s3: S3Storage;
}

function headerValue(value: string | string[] | undefined): string | undefined {
  if (Array.isArray(value)) return value[0];
  return value;
}

function requestParam(request: FastifyRequest, name: string): string {
  const params = request.params as Record<string, string>;
  const value = params[name];
  if (!value) throw Errors.validation(`Missing path parameter: ${name}`);
  return value;
}

function paginationQuery(request: FastifyRequest): { limit: number; offset: number } {
  const query = request.query as Record<string, string | undefined>;
  const limit = Math.min(Math.max(Number(query.limit ?? 50), 1), 100);
  const offset = Math.max(Number(query.offset ?? 0), 0);
  return { limit, offset };
}

function routePath(request: FastifyRequest): string {
  const routeOptions = (request as FastifyRequest & { routeOptions?: { url?: string } }).routeOptions;
  return routeOptions?.url ?? request.url.split("?")[0] ?? request.url;
}

function rawPath(request: FastifyRequest): string {
  return request.url.split("?")[0] ?? request.url;
}

export function buildApp(runtime: AppRuntime): FastifyInstance {
  const app = Fastify({ logger: false, trustProxy: true });
  const { config, logger, reportService } = runtime;
  const openApi = buildOpenApiDocument(config);
  const docsHtml = renderSwaggerHtml(openApi);
  const manualHttpTransactions = new WeakMap<FastifyRequest, ApmTransaction>();

  app.addHook("onRequest", async (request, reply) => {
    const requestId = headerValue(request.headers["x-request-id"]) ?? `req-${randomUUID()}`;
    const traceId = headerValue(request.headers["x-trace-id"]) ?? `trace-${randomUUID()}`;
    const correlationId = headerValue(request.headers["x-correlation-id"]) ?? `corr-${randomUUID()}`;
    request.requestContext = { requestId, traceId, correlationId, startTimeMs: performance.now(), tenant: config.service.tenant };
    reply.header("X-Request-ID", requestId);
    reply.header("X-Trace-ID", traceId);
    reply.header("X-Correlation-ID", correlationId);
    setApmLabels({ request_id: requestId, trace_id: traceId, correlation_id: correlationId, tenant: config.service.tenant });
    const manualTransaction = startApmHttpTransaction(`${request.method} ${rawPath(request)}`, {
      request_id: requestId,
      trace_id: traceId,
      correlation_id: correlationId,
      tenant: config.service.tenant,
      http_method: request.method,
      path: rawPath(request)
    });
    if (manualTransaction) manualHttpTransactions.set(request, manualTransaction);

    const origin = headerValue(request.headers.origin);
    if (origin && config.cors.allowedOrigins.includes(origin)) {
      reply.header("Access-Control-Allow-Origin", origin);
      reply.header("Vary", "Origin");
      reply.header("Access-Control-Allow-Credentials", String(config.cors.allowCredentials));
      reply.header("Access-Control-Allow-Methods", config.cors.allowedMethods.join(","));
      reply.header("Access-Control-Allow-Headers", config.cors.allowedHeaders.join(","));
      reply.header("Access-Control-Max-Age", String(config.cors.maxAgeSeconds));
    }
  });

  app.addHook("preHandler", async (request) => {
    if (request.url.startsWith("/v1/")) await authenticateRequest(request, config, logger);
  });

  app.addHook("onResponse", async (request, reply) => {
    const path = routePath(request);
    const outcome = reply.statusCode >= 500 ? "failure" : "success";
    const labels = {
      route: path,
      http_status_code: reply.statusCode,
      user_id: request.user?.sub ?? null,
      actor_id: request.user?.sub ?? null
    };
    setApmTransactionName(`${request.method} ${path}`);
    setApmOutcome(outcome);
    setApmLabels(labels);
    finishApmHttpTransaction(manualHttpTransactions.get(request), `${request.method} ${path}`, outcome, labels);

    if (shouldSuppressSuccessfulRequestLog(rawPath(request), reply.statusCode)) return;
    logger.info("request completed", {
      logger: "app.request",
      event: "http.request.completed",
      request_id: request.requestContext.requestId,
      trace_id: request.requestContext.traceId,
      correlation_id: request.requestContext.correlationId,
      user_id: request.user?.sub ?? null,
      actor_id: request.user?.sub ?? null,
      method: request.method,
      path,
      status_code: reply.statusCode,
      duration_ms: Number((performance.now() - request.requestContext.startTimeMs).toFixed(1)),
      client_ip: request.ip,
      user_agent: headerValue(request.headers["user-agent"]) ?? null
    });
  });

  app.setNotFoundHandler(async (request, reply) => {
    await reply.status(404).send(errorEnvelope(request, "NOT_FOUND", "Resource not found"));
  });

  app.setErrorHandler(async (error, request, reply) => {
    const zodError = error instanceof ZodError;
    const fastifyError = error as { statusCode?: number; code?: string; validation?: unknown; body?: unknown };
    const fastifyStatusCode = Number(fastifyError.statusCode);
    const fastifyCode = typeof fastifyError.code === "string" ? fastifyError.code : undefined;
    const fastifyValidationError =
      fastifyStatusCode === 400 ||
      fastifyCode === "FST_ERR_CTP_INVALID_JSON_BODY" ||
      fastifyCode === "FST_ERR_VALIDATION" ||
      fastifyCode === "FST_ERR_CTP_EMPTY_JSON_BODY" ||
      fastifyCode === "FST_ERR_CTP_INVALID_MEDIA_TYPE" ||
      Boolean(fastifyError.validation);

    const statusCode = isAppError(error) ? error.statusCode : zodError || fastifyValidationError ? 400 : 500;
    const code = isAppError(error) ? error.errorCode : zodError || fastifyValidationError ? "VALIDATION_ERROR" : "INTERNAL_ERROR";
    const message = isAppError(error)
      ? error.message
      : zodError
        ? "Validation failed"
        : fastifyValidationError
          ? "Invalid request body"
          : "Internal server error";
    const details = isAppError(error)
      ? error.details
      : zodError
        ? { issues: error.issues }
        : fastifyValidationError
          ? { parser_code: fastifyCode ?? "FASTIFY_REQUEST_VALIDATION", reason: error instanceof Error ? error.message : String(error) }
          : {};

    setApmLabels({ error_code: code, status_code: statusCode, path: request.url });

    if (statusCode >= 500) {
      const exception = error instanceof Error ? error : new Error(String(error));
      captureApmError(exception, { error_code: code, path: request.url, status_code: statusCode });
      logger.error(message, {
        logger: "app.error",
        event: "http.request.failed",
        request_id: request.requestContext?.requestId,
        trace_id: request.requestContext?.traceId,
        correlation_id: request.requestContext?.correlationId,
        user_id: request.user?.sub ?? null,
        actor_id: request.user?.sub ?? null,
        method: request.method,
        path: request.url,
        status_code: statusCode,
        error_code: code,
        exception_class: exception.name,
        exception_message: exception.message,
        stack_trace: exception.stack ?? null
      });
    } else if (statusCode === 401 || statusCode === 403) {
      setApmLabels({ security_error: code, status_code: statusCode, path: request.url });
      logger.warn(message, {
        logger: "app.security",
        event: statusCode === 401 ? "authentication.failed" : "authorization.denied",
        request_id: request.requestContext?.requestId,
        trace_id: request.requestContext?.traceId,
        correlation_id: request.requestContext?.correlationId,
        method: request.method,
        path: request.url,
        status_code: statusCode,
        error_code: code
      });
    } else if (statusCode === 400) {
      logger.warn(message, {
        logger: "app.validation",
        event: "http.request.validation_failed",
        request_id: request.requestContext?.requestId,
        trace_id: request.requestContext?.traceId,
        correlation_id: request.requestContext?.correlationId,
        user_id: request.user?.sub ?? null,
        actor_id: request.user?.sub ?? null,
        method: request.method,
        path: request.url,
        status_code: statusCode,
        error_code: code
      });
    }

    if (!reply.sent) await reply.status(statusCode).send(errorEnvelope(request, code, message, details));
  });

  app.get("/hello", async (_request, reply) => {
    const body = { status: "ok", message: `${config.service.name} is running`, service: { name: config.service.name, env: config.service.environment, version: config.service.version } };
    await reply.type("application/json; charset=utf-8").send(JSON.stringify(body, null, 2));
  });

  app.get("/health", async (_request, reply) => {
    const health = await buildHealthResponse(config, runtime.healthDependencies);
    await reply.status(health.status === "ok" ? 200 : 503).type("application/json; charset=utf-8").send(JSON.stringify(health, null, 2));
  });

  app.get("/docs", async (_request, reply) => {
    await reply.type("text/html; charset=utf-8").send(docsHtml);
  });

  app.get("/v1/reports/types", async (request) => success(request, "report types loaded", reportService.listTypes()));
  app.get("/v1/reports/types/:reportType", async (request) => success(request, "report type loaded", reportService.getType(requestParam(request, "reportType"))));

  app.get("/v1/reports/templates", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "templates loaded", await reportService.listTemplates(request.user));
  });
  app.get("/v1/reports/templates/:templateId", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "template loaded", await reportService.getTemplate(request.user, requestParam(request, "templateId")));
  });
  app.post("/v1/reports/templates", async (request, reply) => {
    if (!request.user) throw Errors.unauthorized();
    const body = createTemplateSchema.parse(request.body ?? {});
    await reply.status(201).send(success(request, "template created", await reportService.createTemplate(request.user, body, request)));
  });
  app.put("/v1/reports/templates/:templateId", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    const body = updateTemplateSchema.parse(request.body ?? {});
    return success(request, "template updated", await reportService.updateTemplate(request.user, requestParam(request, "templateId"), body, request));
  });
  app.post("/v1/reports/templates/:templateId/activate", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "template activated", await reportService.setTemplateStatus(request.user, requestParam(request, "templateId"), "ACTIVE", request));
  });
  app.post("/v1/reports/templates/:templateId/deactivate", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "template deactivated", await reportService.setTemplateStatus(request.user, requestParam(request, "templateId"), "INACTIVE", request));
  });

  app.get("/v1/reports/schedules", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "schedules loaded", await reportService.listSchedules(request.user));
  });
  app.get("/v1/reports/schedules/:scheduleId", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "schedule loaded", await reportService.getSchedule(request.user, requestParam(request, "scheduleId")));
  });
  app.post("/v1/reports/schedules", async (request, reply) => {
    if (!request.user) throw Errors.unauthorized();
    const body = createScheduleSchema.parse(request.body ?? {});
    await reply.status(201).send(success(request, "schedule created", await reportService.createSchedule(request.user, body, request)));
  });
  app.put("/v1/reports/schedules/:scheduleId", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    const body = updateScheduleSchema.parse(request.body ?? {});
    return success(request, "schedule updated", await reportService.updateSchedule(request.user, requestParam(request, "scheduleId"), body, request));
  });
  app.post("/v1/reports/schedules/:scheduleId/pause", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "schedule paused", await reportService.setScheduleStatus(request.user, requestParam(request, "scheduleId"), "PAUSED", request));
  });
  app.post("/v1/reports/schedules/:scheduleId/resume", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "schedule resumed", await reportService.setScheduleStatus(request.user, requestParam(request, "scheduleId"), "ACTIVE", request));
  });
  app.delete("/v1/reports/schedules/:scheduleId", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "schedule deleted", await reportService.setScheduleStatus(request.user, requestParam(request, "scheduleId"), "DELETED", request));
  });

  app.get("/v1/reports/queue/summary", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "queue summary loaded", await reportService.queueSummary(request.user));
  });

  app.get("/v1/reports/audit", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    const { limit, offset } = paginationQuery(request);
    return success(request, "audit events loaded", await reportService.listAudit(request.user, limit, offset));
  });
  app.get("/v1/reports/audit/:eventId", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "audit event loaded", await reportService.getAudit(request.user, requestParam(request, "eventId")));
  });

  app.post("/v1/reports", async (request, reply) => {
    if (!request.user) throw Errors.unauthorized();
    const body = createReportRequestSchema.parse(request.body ?? {});
    const data = await reportService.createReport(request.user, body, request);
    await reply.status(201).send(success(request, "report request queued", data));
  });

  app.get("/v1/reports", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    const query = listReportsQuerySchema.parse(request.query ?? {});
    return success(request, "reports loaded", await reportService.listReports(request.user, query));
  });

  app.get("/v1/reports/:reportId", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "report loaded", await reportService.getReport(request.user, requestParam(request, "reportId")));
  });

  app.post("/v1/reports/:reportId/cancel", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "report cancelled", await reportService.cancelReport(request.user, requestParam(request, "reportId"), request));
  });

  app.post("/v1/reports/:reportId/retry", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "report retry queued", await reportService.retryReport(request.user, requestParam(request, "reportId"), request));
  });

  app.post("/v1/reports/:reportId/regenerate", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "report regeneration queued", await reportService.retryReport(request.user, requestParam(request, "reportId"), request));
  });

  app.delete("/v1/reports/:reportId", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "report deleted", await reportService.deleteReport(request.user, requestParam(request, "reportId"), request));
  });

  app.get("/v1/reports/:reportId/metadata", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "report metadata loaded", await reportService.metadata(request.user, requestParam(request, "reportId")));
  });

  app.get("/v1/reports/:reportId/download", async (request, reply) => {
    if (!request.user) throw Errors.unauthorized();
    const { file } = await reportService.getDownloadFile(request.user, requestParam(request, "reportId"), request);
    const object = await runtime.s3.getObject(file.s3_object_key);
    const disposition = `${config.report.downloadContentDisposition}; filename="${file.file_name.replace(/"/g, "")}"`;
    reply.header("Content-Type", object.contentType ?? file.content_type);
    reply.header("Content-Disposition", disposition);
    if (object.contentLength) reply.header("Content-Length", object.contentLength);
    await reply.send(object.body);
  });

  app.get("/v1/reports/:reportId/preview", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "report preview loaded", await reportService.preview(request.user, requestParam(request, "reportId"), request));
  });

  app.get("/v1/reports/:reportId/progress", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "report progress loaded", await reportService.progress(request.user, requestParam(request, "reportId")));
  });

  app.get("/v1/reports/:reportId/events", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "report progress events loaded", await reportService.events(request.user, requestParam(request, "reportId")));
  });

  app.get("/v1/reports/:reportId/files", async (request) => {
    if (!request.user) throw Errors.unauthorized();
    return success(request, "report files loaded", await reportService.files(request.user, requestParam(request, "reportId")));
  });

  return app;
}
