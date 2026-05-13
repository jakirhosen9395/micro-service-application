import { existsSync } from "node:fs";
import { resolve } from "node:path";
import dotenv from "dotenv";

export type RuntimeEnvironment = "development" | "stage" | "production";
export type EnvAlias = RuntimeEnvironment | "dev" | "prod";

export function normalizeEnvironment(value: string | undefined, fallback: RuntimeEnvironment = "development"): RuntimeEnvironment {
  const raw = (value ?? "").trim().toLowerCase();
  if (raw === "dev" || raw === "development") return "development";
  if (raw === "stage" || raw === "staging") return "stage";
  if (raw === "prod" || raw === "production") return "production";
  return fallback;
}

export function envFileSuffix(environment: RuntimeEnvironment): "dev" | "stage" | "prod" {
  if (environment === "development") return "dev";
  if (environment === "stage") return "stage";
  return "prod";
}

export function loadEnvFile(): string | undefined {
  const explicit = process.env.REPORT_ENV_FILE || process.env.ENV_FILE;
  const candidates: string[] = [];

  if (explicit) candidates.push(explicit);

  const requested = normalizeEnvironment(process.env.REPORT_ENV || process.env.REPORT_NODE_ENV || process.env.NODE_ENV);
  candidates.push(`.env.${envFileSuffix(requested)}`);
  candidates.push(".env.dev");

  for (const candidate of candidates) {
    const fullPath = resolve(process.cwd(), candidate);
    if (existsSync(fullPath)) {
      dotenv.config({ path: fullPath, override: false });
      return fullPath;
    }
  }

  return undefined;
}
