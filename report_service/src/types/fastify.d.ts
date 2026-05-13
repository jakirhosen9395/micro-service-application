import "fastify";
import type { RequestContext } from "./request-context.js";
import type { AuthenticatedUser } from "./auth.js";

declare module "fastify" {
  interface FastifyRequest {
    requestContext: RequestContext;
    user?: AuthenticatedUser;
  }
}
