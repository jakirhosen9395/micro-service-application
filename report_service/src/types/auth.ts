export type UserRole = "user" | "admin" | "service" | "system";
export type AdminStatus = "not_requested" | "pending" | "approved" | "rejected" | "suspended";

export interface AuthenticatedUser {
  sub: string;
  jti: string;
  username: string;
  email: string;
  role: UserRole;
  admin_status: AdminStatus;
  tenant: string;
  iss: string;
  aud: string | string[];
  iat: number;
  nbf: number;
  exp: number;
}
