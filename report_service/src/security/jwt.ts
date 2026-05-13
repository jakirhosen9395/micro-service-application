import type { FastifyRequest } from "fastify";
import jwt, { type JwtPayload } from "jsonwebtoken";
import type { AppConfig } from "../config/config.js";
import { Errors } from "../http/errors.js";
import type { AppLogger } from "../logging/logger.js";
import type { AdminStatus, AuthenticatedUser, UserRole } from "../types/auth.js";

const ROLES: UserRole[] = ["user", "admin", "service", "system"];
const ADMIN_STATUSES: AdminStatus[] = ["not_requested", "pending", "approved", "rejected", "suspended"];

function bearerToken(request: FastifyRequest): string {
  const header = request.headers.authorization;
  if (!header) throw Errors.unauthorized("Authentication required");
  const [scheme, token] = header.split(" ");
  if (scheme?.toLowerCase() !== "bearer" || !token) throw Errors.unauthorized("Bearer token required");
  return token;
}

function requireString(payload: JwtPayload, key: string): string {
  const value = payload[key];
  if (typeof value !== "string" || value.length === 0) throw Errors.unauthorized(`JWT claim ${key} is required`);
  return value;
}

function requireNumber(payload: JwtPayload, key: string): number {
  const value = payload[key];
  if (typeof value !== "number" || !Number.isFinite(value)) throw Errors.unauthorized(`JWT claim ${key} is required`);
  return value;
}

export function verifyJwt(token: string, config: AppConfig): AuthenticatedUser {
  let decoded: string | JwtPayload;
  try {
    decoded = jwt.verify(token, config.jwt.secret, {
      algorithms: [config.jwt.algorithm],
      issuer: config.jwt.issuer,
      audience: config.jwt.audience,
      clockTolerance: config.jwt.leewaySeconds
    });
  } catch (error) {
    throw Errors.unauthorized("Invalid or expired token", { reason: error instanceof Error ? error.name : "JwtError" });
  }

  if (typeof decoded === "string") throw Errors.unauthorized("Invalid token payload");

  const role = requireString(decoded, "role") as UserRole;
  const adminStatus = requireString(decoded, "admin_status") as AdminStatus;
  if (!ROLES.includes(role)) throw Errors.unauthorized("Invalid role claim");
  if (!ADMIN_STATUSES.includes(adminStatus)) throw Errors.unauthorized("Invalid admin_status claim");

  return {
    sub: requireString(decoded, "sub"),
    jti: requireString(decoded, "jti"),
    username: requireString(decoded, "username"),
    email: requireString(decoded, "email"),
    role,
    admin_status: adminStatus,
    tenant: requireString(decoded, "tenant"),
    iss: requireString(decoded, "iss"),
    aud: decoded.aud ?? config.jwt.audience,
    iat: requireNumber(decoded, "iat"),
    nbf: requireNumber(decoded, "nbf"),
    exp: requireNumber(decoded, "exp")
  };
}

export async function authenticateRequest(request: FastifyRequest, config: AppConfig, logger: AppLogger): Promise<void> {
  const token = bearerToken(request);
  const user = verifyJwt(token, config);
  if (config.security.requireTenantMatch && user.tenant !== config.service.tenant) {
    logger.warn("tenant mismatch denied", {
      logger: "app.security",
      event: "authorization.tenant_mismatch",
      request_id: request.requestContext.requestId,
      trace_id: request.requestContext.traceId,
      correlation_id: request.requestContext.correlationId,
      user_id: user.sub,
      actor_id: user.sub,
      error_code: "TENANT_MISMATCH",
      extra: { token_tenant: user.tenant, service_tenant: config.service.tenant }
    });
    throw Errors.forbidden("Token tenant does not match service tenant");
  }
  request.user = user;
  request.requestContext.tenant = user.tenant;
  request.requestContext.userId = user.sub;
  request.requestContext.actorId = user.sub;
}
