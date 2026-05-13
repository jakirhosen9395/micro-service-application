import { createHash } from "node:crypto";
import PDFDocument from "pdfkit";
import ExcelJS from "exceljs";
import { stringify } from "csv-stringify/sync";
import type { ReportDatasets, ReportRequestForGeneration } from "./data-loader.js";
import type { ReportFormat } from "../storage/paths.js";

export interface RenderedReport {
  buffer: Buffer;
  contentType: string;
  extension: ReportFormat;
  checksumSha256: string;
  previewSupported: boolean;
}

function checksum(buffer: Buffer): string {
  return createHash("sha256").update(buffer).digest("hex");
}

function flatten(value: unknown): unknown {
  if (value === null || value === undefined) return "";
  if (value instanceof Date) return value.toISOString();
  if (typeof value === "object") return JSON.stringify(value);
  return value;
}

function firstDataset(datasets: ReportDatasets): Record<string, unknown>[] {
  return Object.values(datasets)[0] ?? [];
}

function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function titleFor(report: ReportRequestForGeneration): string {
  return `${report.report_type} (${report.report_id})`;
}

export async function renderReport(report: ReportRequestForGeneration, datasets: ReportDatasets): Promise<RenderedReport> {
  const format = report.format as ReportFormat;
  if (format === "json") return renderJson(report, datasets);
  if (format === "csv") return renderCsv(report, datasets);
  if (format === "html") return renderHtml(report, datasets);
  if (format === "pdf") return renderPdf(report, datasets);
  if (format === "xlsx") return renderXlsx(report, datasets);
  throw new Error(`Unsupported report format: ${format}`);
}

function renderJson(report: ReportRequestForGeneration, datasets: ReportDatasets): RenderedReport {
  const buffer = Buffer.from(JSON.stringify({ report, datasets, generated_at: new Date().toISOString() }, null, 2));
  return { buffer, contentType: "application/json; charset=utf-8", extension: "json", checksumSha256: checksum(buffer), previewSupported: true };
}

function renderCsv(report: ReportRequestForGeneration, datasets: ReportDatasets): RenderedReport {
  const rows = firstDataset(datasets);
  const normalized = rows.map((row) => Object.fromEntries(Object.entries(row).map(([key, value]) => [key, flatten(value)])));
  const buffer = Buffer.from(stringify(normalized, { header: true }));
  return { buffer, contentType: "text/csv; charset=utf-8", extension: "csv", checksumSha256: checksum(buffer), previewSupported: true };
}

function renderHtml(report: ReportRequestForGeneration, datasets: ReportDatasets): RenderedReport {
  const sections = Object.entries(datasets).map(([name, rows]) => {
    const columns = [...new Set(rows.flatMap((row) => Object.keys(row)))];
    const header = columns.map((column) => `<th>${escapeHtml(column)}</th>`).join("");
    const body = rows.map((row) => `<tr>${columns.map((column) => `<td>${escapeHtml(flatten(row[column]))}</td>`).join("")}</tr>`).join("");
    return `<section><h2>${escapeHtml(name)}</h2><p>${rows.length} row(s)</p><table><thead><tr>${header}</tr></thead><tbody>${body}</tbody></table></section>`;
  }).join("\n");
  const html = `<!doctype html><html><head><meta charset="utf-8"><title>${escapeHtml(titleFor(report))}</title><style>body{font-family:Arial,sans-serif;margin:32px}table{border-collapse:collapse;width:100%;margin-bottom:24px}th,td{border:1px solid #ddd;padding:6px;font-size:12px;text-align:left}th{background:#f4f4f4}</style></head><body><h1>${escapeHtml(titleFor(report))}</h1><p>Generated at ${escapeHtml(new Date().toISOString())}</p>${sections}</body></html>`;
  const buffer = Buffer.from(html);
  return { buffer, contentType: "text/html; charset=utf-8", extension: "html", checksumSha256: checksum(buffer), previewSupported: true };
}

async function renderPdf(report: ReportRequestForGeneration, datasets: ReportDatasets): Promise<RenderedReport> {
  const doc = new PDFDocument({ size: "A4", margin: 42 });
  const chunks: Buffer[] = [];
  doc.on("data", (chunk: Buffer) => chunks.push(chunk));
  const finished = new Promise<void>((resolve, reject) => {
    doc.on("end", () => resolve());
    doc.on("error", reject);
  });

  doc.fontSize(18).text(titleFor(report), { underline: true });
  doc.moveDown();
  doc.fontSize(10).text(`Generated at: ${new Date().toISOString()}`);
  doc.text(`Target user: ${report.target_user_id}`);
  doc.text(`Tenant: ${report.tenant}`);
  doc.moveDown();

  for (const [name, rows] of Object.entries(datasets)) {
    doc.fontSize(14).text(name);
    doc.fontSize(9).text(`${rows.length} row(s)`);
    doc.moveDown(0.5);
    for (const row of rows.slice(0, 100)) {
      doc.fontSize(8).text(JSON.stringify(row, null, 2), { width: 500 });
      doc.moveDown(0.3);
      if (doc.y > 740) doc.addPage();
    }
    if (rows.length > 100) doc.fontSize(8).text(`... truncated in PDF preview after 100 rows for section ${name}`);
    doc.moveDown();
  }

  doc.end();
  await finished;
  const buffer = Buffer.concat(chunks);
  return { buffer, contentType: "application/pdf", extension: "pdf", checksumSha256: checksum(buffer), previewSupported: false };
}

async function renderXlsx(report: ReportRequestForGeneration, datasets: ReportDatasets): Promise<RenderedReport> {
  const workbook = new ExcelJS.Workbook();
  workbook.creator = "report_service";
  workbook.created = new Date();
  workbook.modified = new Date();

  for (const [name, rows] of Object.entries(datasets)) {
    const worksheet = workbook.addWorksheet(name.slice(0, 31) || "report");
    const columns = [...new Set(rows.flatMap((row) => Object.keys(row)))];
    worksheet.columns = columns.map((column) => ({ header: column, key: column, width: Math.min(Math.max(column.length + 4, 14), 60) }));
    for (const row of rows) {
      worksheet.addRow(Object.fromEntries(Object.entries(row).map(([key, value]) => [key, flatten(value)])));
    }
  }

  const arrayBuffer = await workbook.xlsx.writeBuffer();
  const buffer = Buffer.from(arrayBuffer);
  return { buffer, contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", extension: "xlsx", checksumSha256: checksum(buffer), previewSupported: false };
}
