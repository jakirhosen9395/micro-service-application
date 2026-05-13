import type { FastifyRequest } from "fastify";

export interface SuccessEnvelope<T> {
  status: "ok";
  message: string;
  data: T;
  request_id: string;
  trace_id: string;
  timestamp: string;
}

export interface ErrorEnvelope {
  status: "error";
  message: string;
  error_code: string;
  details: Record<string, unknown>;
  path: string;
  request_id: string;
  trace_id: string;
  timestamp: string;
}

export function success<T>(request: FastifyRequest, message: string, data: T): SuccessEnvelope<T> {
  return {
    status: "ok",
    message,
    data,
    request_id: request.requestContext.requestId,
    trace_id: request.requestContext.traceId,
    timestamp: new Date().toISOString()
  };
}

export function errorEnvelope(
  request: FastifyRequest,
  statusCode: string,
  message: string,
  details: Record<string, unknown> = {}
): ErrorEnvelope {
  return {
    status: "error",
    message,
    error_code: statusCode,
    details,
    path: request.url,
    request_id: request.requestContext?.requestId ?? "unknown",
    trace_id: request.requestContext?.traceId ?? "unknown",
    timestamp: new Date().toISOString()
  };
}
