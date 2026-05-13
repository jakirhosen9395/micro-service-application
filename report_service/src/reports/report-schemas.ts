import { z } from "zod";

export const reportFormatSchema = z.enum(["pdf", "xlsx", "csv", "json", "html"]);
export const reportStatusSchema = z.enum(["QUEUED", "PROCESSING", "COMPLETED", "FAILED", "CANCELLED", "DELETED", "EXPIRED"]);

const jsonObject = z.record(z.string(), z.unknown());

export const createReportRequestSchema = z.object({
  report_type: z.string().min(1),
  target_user_id: z.string().min(1).optional(),
  format: reportFormatSchema.optional(),
  date_from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  date_to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  filters: jsonObject.default({}),
  options: jsonObject.default({})
}).refine((value) => !value.date_from || !value.date_to || value.date_from <= value.date_to, {
  message: "date_from must be before or equal to date_to",
  path: ["date_from"]
});

export const listReportsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).default(0),
  status: reportStatusSchema.optional(),
  target_user_id: z.string().min(1).optional()
});

export const createTemplateSchema = z.object({
  report_type: z.string().min(1),
  name: z.string().min(1).max(160),
  description: z.string().max(1000).optional(),
  format: reportFormatSchema.default("pdf"),
  template_content: z.string().max(65536).default("{}"),
  schema: jsonObject.default({}),
  style: jsonObject.default({})
});

export const updateTemplateSchema = createTemplateSchema.partial().refine((value) => Object.keys(value).length > 0, { message: "At least one field is required" });

export const createScheduleSchema = z.object({
  target_user_id: z.string().min(1).optional(),
  report_type: z.string().min(1),
  format: reportFormatSchema.optional(),
  cron_expression: z.string().min(5).max(120),
  timezone: z.string().min(1).default("Asia/Dhaka"),
  filters: jsonObject.default({}),
  options: jsonObject.default({})
});

export const updateScheduleSchema = createScheduleSchema.partial().refine((value) => Object.keys(value).length > 0, { message: "At least one field is required" });

export type CreateReportRequest = z.infer<typeof createReportRequestSchema>;
export type ListReportsQuery = z.infer<typeof listReportsQuerySchema>;
export type CreateTemplateRequest = z.infer<typeof createTemplateSchema>;
export type UpdateTemplateRequest = z.infer<typeof updateTemplateSchema>;
export type CreateScheduleRequest = z.infer<typeof createScheduleSchema>;
export type UpdateScheduleRequest = z.infer<typeof updateScheduleSchema>;
