export class AppError extends Error {
  public readonly statusCode: number;
  public readonly errorCode: string;
  public readonly details: Record<string, unknown>;

  public constructor(statusCode: number, errorCode: string, message: string, details: Record<string, unknown> = {}) {
    super(message);
    this.statusCode = statusCode;
    this.errorCode = errorCode;
    this.details = details;
  }
}

export function isAppError(error: unknown): error is AppError {
  return error instanceof AppError;
}

export const Errors = {
  unauthorized(message = "Authentication required", details: Record<string, unknown> = {}) {
    return new AppError(401, "UNAUTHORIZED", message, details);
  },
  forbidden(message = "Forbidden", details: Record<string, unknown> = {}) {
    return new AppError(403, "FORBIDDEN", message, details);
  },
  notFound(message = "Resource not found", details: Record<string, unknown> = {}) {
    return new AppError(404, "NOT_FOUND", message, details);
  },
  conflict(message = "Conflict", details: Record<string, unknown> = {}) {
    return new AppError(409, "CONFLICT", message, details);
  },
  validation(message = "Validation failed", details: Record<string, unknown> = {}) {
    return new AppError(400, "VALIDATION_ERROR", message, details);
  },
  notImplemented(message = "Not implemented", details: Record<string, unknown> = {}) {
    return new AppError(501, "NOT_IMPLEMENTED", message, details);
  },
  dependency(message = "Dependency unavailable", details: Record<string, unknown> = {}) {
    return new AppError(503, "DEPENDENCY_UNAVAILABLE", message, details);
  }
};
