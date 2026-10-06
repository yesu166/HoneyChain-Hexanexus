/**
 * The portal's authentication/authorization state model.
 *
 * A loose pair of booleans (`isLoggedIn` + `isDemo`) is what allowed a real
 * session and a synthetic demo workspace to be true at the same time, which is
 * how "Demo Admin" ended up rendered over a live JWT. This module replaces that
 * with ONE discriminated state, so "live and demo" is not representable.
 *
 *   unauthenticated  -> nothing signed in; the login screen
 *   live-authenticating -> a credential check is in flight
 *   live-authenticated  -> a real JWT + a real /auth/me
 *   live-error          -> the operator is live but HoneyChain is unreachable;
 *                          the session is PRESERVED, never downgraded
 *   demo-preview        -> an explicitly requested, clearly labelled preview
 *
 * Invariants enforced here and relied on by every screen:
 *   1. Only a successful /auth/me produces `live-authenticated`.
 *   2. `live-error` keeps the token. A dropped connection is not a logout.
 *   3. Nothing but an explicit `enterDemo` call produces `demo-preview`.
 *   4. Reaching a live state discards every demo marker.
 */
import type { DataMode, HoneyChainApi, Role, UserMe } from "./types";

export type AuthPhase =
  | "unauthenticated"
  | "live-authenticating"
  | "live-authenticated"
  /** The operator is authenticated against HoneyChain but it cannot be reached. */
  | LiveErrorPhase
  | "demo-preview";

/** Narrowed view used by the UI: is this a live, authoritative session? */
export function isLive(phase: AuthPhase): boolean {
  return phase === "live-authenticated" || isLiveError(phase);
}

export type LiveErrorPhase = { readonly kind: "live-error"; readonly reason: string };

export function isLiveError(phase: AuthPhase): phase is LiveErrorPhase {
  return typeof phase === "object" && phase.kind === "live-error";
}

export function isDemo(phase: AuthPhase): boolean {
  return phase === "demo-preview";
}

/** Only a confirmed live session may be used as a data source. */
export function modeFor(phase: AuthPhase): DataMode {
  return isDemo(phase) ? "demo" : "live";
}

export function describePhase(phase: AuthPhase): string {
  switch (phase) {
    case "unauthenticated":
      return "Signed out";
    case "live-authenticating":
      return "Signing in…";
    case "live-authenticated":
      return "Live session";
    case "demo-preview":
      return "Demo preview — not HoneyChain data";
    default:
      return isLiveError(phase)
        ? `Live session · HoneyChain unreachable: ${phase.reason}`
        : "Unknown";
  }
}

export interface AuthState {
  user: UserMe | null;
  phase: AuthPhase;
  /** True only while a credential/identity check is in flight. */
  loading: boolean;
  mode: DataMode;
  api: HoneyChainApi;
  /** Real reachability of the HoneyChain origin. Never optimistic. */
  connection: "CONNECTING" | "CONNECTED" | "OFFLINE";
  login: (identifier: string, password: string) => Promise<UserMe>;
  enterDemo: (role: Role | string) => UserMe;
  logout: () => void;
  refreshConnection: () => void;
}
