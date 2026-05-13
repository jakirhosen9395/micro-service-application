export interface RequestContext {
  requestId: string;
  traceId: string;
  correlationId: string;
  startTimeMs: number;
  tenant?: string;
  userId?: string;
  actorId?: string;
}
