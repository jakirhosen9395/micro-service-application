import type { AppConfig } from "../config/config.js";

const SWAGGER_UI_VERSION = "5.19.0";

const responseOk = { description: "OK" };
const responseCreated = { description: "Created" };
const responseBadRequest = { description: "Bad request" };
const responseUnauthorized = { description: "Authentication required" };
const responseForbidden = { description: "Forbidden" };
const responseNotFound = { description: "Not found" };
const responseConflict = { description: "Conflict" };
const responseUnhealthy = { description: "At least one dependency is down" };
const responseNotImplemented = { description: "Not implemented" };

function pathParam(name: string) {
  return { name, in: "path", required: true, schema: { type: "string" } };
}

function protectedGet(summary: string, parameters: unknown[] = []) {
  return {
    summary,
    security: [{ bearerAuth: [] }],
    parameters,
    responses: {
      "200": responseOk,
      "401": responseUnauthorized,
      "403": responseForbidden,
      "404": responseNotFound
    }
  };
}

function protectedMutation(summary: string, parameters: unknown[] = [], body?: Record<string, unknown>) {
  return {
    summary,
    security: [{ bearerAuth: [] }],
    parameters,
    requestBody: body
      ? {
          required: true,
          content: {
            "application/json": {
              schema: { type: "object", additionalProperties: true },
              example: body
            }
          }
        }
      : undefined,
    responses: {
      "200": responseOk,
      "201": responseCreated,
      "400": responseBadRequest,
      "401": responseUnauthorized,
      "403": responseForbidden,
      "404": responseNotFound,
      "409": responseConflict
    }
  };
}

export function buildOpenApiDocument(config: AppConfig): Record<string, unknown> {
  const reportExample = {
    report_type: "calculator_history_report",
    target_user_id: "optional-target-user-id",
    format: "pdf",
    date_from: "2026-05-01",
    date_to: "2026-05-09",
    filters: {},
    options: {
      include_summary: true,
      include_charts: true,
      include_raw_data: false,
      timezone: "Asia/Dhaka",
      locale: "en",
      title: "My Report"
    }
  };

  return {
    openapi: "3.0.3",
    info: {
      title: "Report Service API",
      version: config.service.version,
      description: "Interactive API console for report_service. Login through auth_service, copy access_token, click Authorize, and paste only the token value. Swagger sends Authorization: Bearer <token>."
    },
    tags: [
      { name: "system", description: "Public system endpoints" },
      { name: "reports", description: "JWT-protected report APIs" },
      { name: "templates", description: "JWT-protected report template APIs" },
      { name: "schedules", description: "JWT-protected report schedule APIs" },
      { name: "observability", description: "JWT-protected queue, progress, and audit APIs" }
    ],
    components: {
      securitySchemes: {
        bearerAuth: {
          type: "http",
          scheme: "bearer",
          bearerFormat: "JWT",
          description: "Paste only the access_token value from auth_service. Swagger sends Authorization: Bearer <token>."
        }
      },
      schemas: {
        ReportRequest: {
          type: "object",
          properties: {
            report_type: { type: "string", example: "calculator_history_report" },
            target_user_id: { type: "string", example: "optional-target-user-id" },
            format: { type: "string", enum: ["pdf", "xlsx", "csv", "json", "html"], example: "pdf" },
            date_from: { type: "string", example: "2026-05-01" },
            date_to: { type: "string", example: "2026-05-09" },
            filters: { type: "object", additionalProperties: true, example: {} },
            options: { type: "object", additionalProperties: true, example: { include_summary: true } }
          },
          required: ["report_type"]
        },
        TemplateRequest: {
          type: "object",
          properties: {
            report_type: { type: "string", example: "calculator_history_report" },
            name: { type: "string", example: "Support PDF" },
            description: { type: "string", example: "Support investigation report template" },
            format: { type: "string", enum: ["pdf", "xlsx", "csv", "json", "html"], example: "pdf" },
            template_content: { type: "string", example: "{}" },
            schema: { type: "object", additionalProperties: true, example: { visible_columns: ["operation", "status", "occurred_at"] } },
            style: { type: "object", additionalProperties: true, example: { logo_text: "Micro App", footer_text: "Internal" } }
          },
          required: ["report_type", "name"]
        },
        ScheduleRequest: {
          type: "object",
          properties: {
            report_type: { type: "string", example: "todo_summary_report" },
            target_user_id: { type: "string", example: "optional-target-user-id" },
            format: { type: "string", enum: ["pdf", "xlsx", "csv", "json", "html"], example: "pdf" },
            cron_expression: { type: "string", example: "0 9 * * *" },
            timezone: { type: "string", example: "Asia/Dhaka" },
            filters: { type: "object", additionalProperties: true, example: {} },
            options: { type: "object", additionalProperties: true, example: { include_summary: true } }
          },
          required: ["report_type", "cron_expression"]
        }
      }
    },
    paths: {
      "/hello": {
        get: { tags: ["system"], security: [], summary: "Service identity check", responses: { "200": responseOk } }
      },
      "/health": {
        get: { tags: ["system"], security: [], summary: "Dependency health check", responses: { "200": responseOk, "503": responseUnhealthy } }
      },
      "/docs": {
        get: { tags: ["system"], security: [], summary: "Swagger UI", responses: { "200": { description: "HTML Swagger UI" } } }
      },
      "/v1/reports/types": { get: { ...protectedGet("List supported report types"), tags: ["reports"] } },
      "/v1/reports/types/{reportType}": { get: { ...protectedGet("Get one report type", [pathParam("reportType")]), tags: ["reports"] } },
      "/v1/reports": {
        post: { ...protectedMutation("Request asynchronous report", [], reportExample), tags: ["reports"] },
        get: { ...protectedGet("List reports requested by caller"), tags: ["reports"] }
      },
      "/v1/reports/{reportId}": {
        get: { ...protectedGet("Get report status", [pathParam("reportId")]), tags: ["reports"] },
        delete: { ...protectedMutation("Soft-delete report", [pathParam("reportId")]), tags: ["reports"] }
      },
      "/v1/reports/{reportId}/cancel": { post: { ...protectedMutation("Cancel queued or processing report", [pathParam("reportId")]), tags: ["reports"] } },
      "/v1/reports/{reportId}/retry": { post: { ...protectedMutation("Retry failed report", [pathParam("reportId")]), tags: ["reports"] } },
      "/v1/reports/{reportId}/regenerate": { post: { ...protectedMutation("Regenerate a failed report", [pathParam("reportId")]), tags: ["reports"] } },
      "/v1/reports/{reportId}/metadata": { get: { ...protectedGet("Get completed report metadata", [pathParam("reportId")]), tags: ["reports"] } },
      "/v1/reports/{reportId}/download": {
        get: {
          tags: ["reports"],
          summary: "Download completed report file from S3",
          security: [{ bearerAuth: [] }],
          parameters: [pathParam("reportId")],
          responses: { "200": responseOk, "401": responseUnauthorized, "403": responseForbidden, "404": responseNotFound, "409": responseConflict }
        }
      },
      "/v1/reports/{reportId}/preview": { get: { ...protectedGet("Preview report content", [pathParam("reportId")]), tags: ["reports"] } },
      "/v1/reports/{reportId}/progress": { get: { ...protectedGet("Get report progress", [pathParam("reportId")]), tags: ["observability"] } },
      "/v1/reports/{reportId}/events": { get: { ...protectedGet("Get report progress events", [pathParam("reportId")]), tags: ["observability"] } },
      "/v1/reports/{reportId}/files": { get: { ...protectedGet("Get report files", [pathParam("reportId")]), tags: ["reports"] } },
      "/v1/reports/templates": {
        get: { ...protectedGet("List report templates"), tags: ["templates"] },
        post: { ...protectedMutation("Create report template", [], { report_type: "calculator_history_report", name: "Support PDF", format: "pdf", template_content: "{}", schema: { visible_columns: ["operation", "status", "occurred_at"] }, style: { logo_text: "Micro App", footer_text: "Internal" } }), tags: ["templates"] }
      },
      "/v1/reports/templates/{templateId}": {
        get: { ...protectedGet("Get report template", [pathParam("templateId")]), tags: ["templates"] },
        put: { ...protectedMutation("Update report template", [pathParam("templateId")], { name: "Updated template", style: { footer_text: "Confidential" } }), tags: ["templates"] }
      },
      "/v1/reports/templates/{templateId}/activate": { post: { ...protectedMutation("Activate report template", [pathParam("templateId")]), tags: ["templates"] } },
      "/v1/reports/templates/{templateId}/deactivate": { post: { ...protectedMutation("Deactivate report template", [pathParam("templateId")]), tags: ["templates"] } },
      "/v1/reports/schedules": {
        get: { ...protectedGet("List report schedules"), tags: ["schedules"] },
        post: { ...protectedMutation("Create report schedule", [], { report_type: "todo_summary_report", format: "pdf", cron_expression: "0 9 * * *", timezone: "Asia/Dhaka", filters: {}, options: { include_summary: true } }), tags: ["schedules"] }
      },
      "/v1/reports/schedules/{scheduleId}": {
        get: { ...protectedGet("Get report schedule", [pathParam("scheduleId")]), tags: ["schedules"] },
        put: { ...protectedMutation("Update report schedule", [pathParam("scheduleId")], { cron_expression: "0 8 * * 1", timezone: "Asia/Dhaka" }), tags: ["schedules"] },
        delete: { ...protectedMutation("Delete report schedule", [pathParam("scheduleId")]), tags: ["schedules"] }
      },
      "/v1/reports/schedules/{scheduleId}/pause": { post: { ...protectedMutation("Pause report schedule", [pathParam("scheduleId")]), tags: ["schedules"] } },
      "/v1/reports/schedules/{scheduleId}/resume": { post: { ...protectedMutation("Resume report schedule", [pathParam("scheduleId")]), tags: ["schedules"] } },
      "/v1/reports/queue/summary": { get: { ...protectedGet("Queue summary for approved admin/service/system actors"), tags: ["observability"] } },
      "/v1/reports/audit": { get: { ...protectedGet("List report audit events"), tags: ["observability"] } },
      "/v1/reports/audit/{eventId}": { get: { ...protectedGet("Get one report audit event", [pathParam("eventId")]), tags: ["observability"] } }
    }
  };
}

function escapeForHtmlScript(value: Record<string, unknown>): string {
  return JSON.stringify(value).replace(/</g, "\\u003c");
}

export function renderSwaggerHtml(openApiDocument: Record<string, unknown>): string {
  const spec = escapeForHtmlScript(openApiDocument);
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Report Service API</title>
  <link rel="icon" href="data:," />
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@${SWAGGER_UI_VERSION}/swagger-ui.css" />
  <style>
    html, body {
      margin: 0;
      padding: 0;
      width: 100%;
      min-height: 100%;
      background: #ffffff;
    }
    #swagger-ui {
      width: 100%;
    }
    .swagger-ui .topbar {
      display: none;
    }
    .swagger-ui .wrapper {
      max-width: 1460px;
      padding: 0 20px;
    }
    .swagger-ui .scheme-container {
      padding: 20px;
      box-shadow: none;
      border-bottom: 1px solid #e5e7eb;
    }
  </style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@${SWAGGER_UI_VERSION}/swagger-ui-bundle.js"></script>
  <script src="https://unpkg.com/swagger-ui-dist@${SWAGGER_UI_VERSION}/swagger-ui-standalone-preset.js"></script>
  <script>
    const openApiSpec = ${spec};
    openApiSpec.servers = [
      {
        url: window.location.origin,
        description: "same-origin server"
      }
    ];

    function safeRandomId(prefix) {
      if (window.crypto && typeof window.crypto.randomUUID === 'function') {
        return prefix + '-' + window.crypto.randomUUID();
      }
      return prefix + '-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 12);
    }

    function normalizeAuthorizationHeader(headers) {
      const current = headers['Authorization'] || headers['authorization'];
      if (!current) {
        return;
      }
      let value = String(current).trim();
      if (!value) {
        return;
      }
      const lower = value.toLowerCase();
      if (lower.startsWith('bearer bearer ')) {
        value = 'Bearer ' + value.substring(14).trim();
      } else if (!lower.startsWith('bearer ') && value.split('.').length === 3) {
        value = 'Bearer ' + value;
      }
      headers['Authorization'] = value;
      if (headers['authorization']) {
        delete headers['authorization'];
      }
    }

    window.ui = SwaggerUIBundle({
      spec: openApiSpec,
      dom_id: '#swagger-ui',
      layout: 'StandaloneLayout',
      deepLinking: true,
      persistAuthorization: true,
      displayRequestDuration: true,
      tryItOutEnabled: true,
      supportedSubmitMethods: ['get', 'post', 'put', 'patch', 'delete', 'options', 'head'],
      filter: true,
      docExpansion: 'list',
      defaultModelsExpandDepth: -1,
      defaultModelExpandDepth: -1,
      validatorUrl: null,
      syntaxHighlight: {
        activated: false
      },
      presets: [
        SwaggerUIBundle.presets.apis,
        SwaggerUIStandalonePreset
      ],
      requestInterceptor: (req) => {
        req.headers = req.headers || {};
        normalizeAuthorizationHeader(req.headers);
        if (!req.headers['X-Request-ID']) {
          req.headers['X-Request-ID'] = safeRandomId('req');
        }
        if (!req.headers['X-Trace-ID']) {
          req.headers['X-Trace-ID'] = safeRandomId('trace');
        }
        if (!req.headers['X-Correlation-ID']) {
          req.headers['X-Correlation-ID'] = safeRandomId('corr');
        }
        return req;
      },
      responseInterceptor: (res) => res
    });
  </script>
</body>
</html>`;
}
