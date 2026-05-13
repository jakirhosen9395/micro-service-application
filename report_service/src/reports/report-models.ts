import type { ReportFormat } from "../storage/paths.js";

export type ReportStatus = "QUEUED" | "PROCESSING" | "COMPLETED" | "FAILED" | "CANCELLED" | "DELETED" | "EXPIRED";
export type ReportJobStatus = "QUEUED" | "PROCESSING" | "COMPLETED" | "FAILED" | "CANCELLED";
export type ReportProgressStage = "queued" | "loading_data" | "rendering" | "uploading" | "completed" | "failed" | "cancelled";

export interface ReportRequestRecord {
  report_id: string;
  tenant: string;
  requester_user_id: string;
  target_user_id: string;
  report_type: string;
  format: ReportFormat;
  status: ReportStatus;
  filters: Record<string, unknown>;
  options: Record<string, unknown>;
  date_from: string | null;
  date_to: string | null;
  requested_at: string;
  queued_at: string | null;
  processing_started_at: string | null;
  completed_at: string | null;
  failed_at: string | null;
  cancelled_at: string | null;
  expired_at: string | null;
  error_code: string | null;
  error_message: string | null;
  request_id: string | null;
  trace_id: string | null;
  correlation_id: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface ReportFileRecord {
  file_id: string;
  report_id: string;
  tenant: string;
  format: ReportFormat;
  file_name: string;
  content_type: string;
  file_size_bytes: number;
  s3_bucket: string;
  s3_object_key: string;
  checksum_sha256: string;
  preview_supported: boolean;
  download_count: number;
  last_downloaded_at: string | null;
  download_expires_at: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface ReportProgressRecord {
  report_id: string;
  tenant: string;
  status: ReportJobStatus;
  progress_percent: number;
  progress_stage: ReportProgressStage;
  started_at: string | null;
  finished_at: string | null;
  duration_ms: number | null;
  error_code: string | null;
  error_message: string | null;
  updated_at: string;
  last_message?: string | null;
}

export interface ReportTemplateRecord {
  template_id: string;
  tenant: string;
  report_type: string;
  name: string;
  description: string | null;
  format: ReportFormat;
  template_engine: string;
  template_content: string;
  schema: Record<string, unknown>;
  style: Record<string, unknown>;
  version: number;
  status: "DRAFT" | "ACTIVE" | "INACTIVE";
  created_by: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface ReportScheduleRecord {
  schedule_id: string;
  tenant: string;
  owner_user_id: string;
  target_user_id: string;
  report_type: string;
  format: ReportFormat;
  cron_expression: string;
  timezone: string;
  filters: Record<string, unknown>;
  options: Record<string, unknown>;
  status: "ACTIVE" | "PAUSED" | "DELETED";
  last_run_at: string | null;
  next_run_at: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface ReportAuditRecord {
  event_id: string;
  event_type: string;
  report_id: string | null;
  actor_id: string | null;
  target_user_id: string | null;
  s3_bucket: string | null;
  s3_object_key: string | null;
  payload: Record<string, unknown>;
  created_at: string;
}
