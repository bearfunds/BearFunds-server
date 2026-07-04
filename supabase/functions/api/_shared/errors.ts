// Q21: opaque API error codes. Raw upstream detail (Postgres messages carry
// table names, policy names, constraint names) must NEVER reach the wire - it
// is an info-disclosure channel. Failures map to a closed enum with FIXED
// messages; full detail belongs in the function logs only. ValidationError is
// the single exception: its texts are authored contract-side messages with no
// DB internals, and the client needs them verbatim.

import { ValidationError } from "./validation.ts";

export type ApiErrorCode = "AUTH" | "VALIDATION" | "RLS_DENIED" | "CONFLICT" | "INTERNAL";

/** Wraps an upstream DB failure, preserving the SQLSTATE for classification
 *  while keeping the raw message OFF the wire (logs only). */
export class UpstreamDbError extends Error {
  pgCode?: string;
  constructor(message: string, pgCode?: string) {
    super(message);
    this.name = "UpstreamDbError";
    this.pgCode = pgCode;
  }
}

export interface ClassifiedError {
  code: ApiErrorCode;
  http: number;
  message: string;
}

const GENERIC = "The request could not be completed.";

// Only EXACT SQLSTATE codes get specific labels; everything unknown defaults
// to INTERNAL (fail-generic, never fail-leaky).
export function classifyApiError(e: unknown): ClassifiedError {
  if (e instanceof ValidationError) {
    return { code: "VALIDATION", http: 400, message: e.message };
  }
  if (e instanceof UpstreamDbError) {
    if (e.pgCode === "42501") return { code: "RLS_DENIED", http: 403, message: "Permission denied for this family." };
    if (e.pgCode === "23505") return { code: "CONFLICT", http: 409, message: "The change conflicts with existing data." };
    return { code: "INTERNAL", http: 500, message: GENERIC };
  }
  return { code: "INTERNAL", http: 500, message: GENERIC };
}
