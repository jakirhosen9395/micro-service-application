import type { AppConfig } from "../config/config.js";

export type ReportFormat = "pdf" | "xlsx" | "csv" | "json" | "html";

export function extensionForFormat(format: ReportFormat): string {
  return format === "xlsx" ? "xlsx" : format;
}

function pad(value: number): string {
  return String(value).padStart(2, "0");
}

function safeSegment(value: string): string {
  return value.replace(/[^a-zA-Z0-9_.@-]/g, "_");
}

export function reportFileKey(
  config: AppConfig,
  tenant: string,
  targetUserId: string,
  reportId: string,
  format: ReportFormat,
  date = new Date()
): string {
  const yyyy = String(date.getUTCFullYear());
  const mm = pad(date.getUTCMonth() + 1);
  const dd = pad(date.getUTCDate());
  return `${config.service.name}/${config.service.environment}/tenant/${safeSegment(tenant)}/users/${safeSegment(targetUserId)}/reports/${yyyy}/${mm}/${dd}/${safeSegment(reportId)}.${extensionForFormat(format)}`;
}

export function auditEventKey(
  config: AppConfig,
  tenant: string,
  actorId: string,
  eventType: string,
  eventId: string,
  date = new Date()
): string {
  const yyyy = String(date.getUTCFullYear());
  const mm = pad(date.getUTCMonth() + 1);
  const dd = pad(date.getUTCDate());
  const hh = pad(date.getUTCHours());
  const min = pad(date.getUTCMinutes());
  const ss = pad(date.getUTCSeconds());
  const eventSlug = eventType.replace(/[^a-z0-9]+/gi, "_").toLowerCase();
  return `${config.service.name}/${config.service.environment}/tenant/${safeSegment(tenant)}/users/${safeSegment(actorId)}/events/${yyyy}/${mm}/${dd}/${hh}${min}${ss}_${eventSlug}_${safeSegment(eventId)}.json`;
}
