import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import {
  clearDemoState,
  getStoredDemoUser,
  getStoredMode,
  getToken,
  probeConnection,
  setStoredDemoUser,
  setStoredMode,
  setToken,
  setUnauthorizedHandler,
} from "./client";
import { demoUserForRole, resetDemo, setDemoUser } from "./demo";
import { demoApi } from "./demo";
import { liveApi } from "./live-api";
import type { AuthState } from "./auth-state";
import { modeFor, type AuthPhase } from "./auth-state";
import type { UserMe } from "./types";
import { homeForRole } from "./format";

const Ctx = createContext<AuthState | null>(null);

/** Pull the HTTP status off whatever the transport threw, if it has one. */
function statusOf(error: unknown): number {
  const raw = (error as { status?: unknown } | null)?.status;
  return typeof raw === "number" ? raw : 0;
}

/**
 * True when HoneyChain has rejected the session itself. This is the only condition
 * that discards a stored token: everything else is treated as a transport
 * problem, because throwing away a good session to a flaky network is its own
 * kind of lie.
 */
function isRejectedSession(status: number): boolean {
  return status === 401 || status === 403;
}

/**
 * True when the request will never succeed as sent, so retrying is pointless
 * and the session should be treated as absent.
 *
 * 429 is deliberately absent: rate limiting clears on its own, and reporting it
 * as a rejected identity would be wrong.
 */
function isDefinitive(status: number): boolean {
  return status === 400 || isRejectedSession(status) || status === 422;
}

/** Plain-language reason for a live failure, derived only from the status. */
function reasonFor(error: unknown): string {
  const status = statusOf(error);
  if (status === 0) return "the API could not be reached";
  if (status === 429) return "the API is rate limiting sign-in attempts";
  return `the API answered ${status}`;
}

/**
 * The single place the portal decides whether it is talking to HoneyChain or to a
 * labelled preview. Screens read `phase`/`mode` from context and never infer it
 * from the presence of a cached record.
 */
export function HoneyAuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<UserMe | null>(null);
  const [phase, setPhase] = useState<AuthPhase>("live-authenticating");
  const [connection, setConnection] = useState<AuthState["connection"]>("CONNECTING");

  const logout = useCallback(() => {
    setToken(null);
    // Signing out also drops any demo marker, so the next visit cannot open a
    // workspace the operator never asked for.
    clearDemoState();
    setUser(null);
    setPhase("unauthenticated");
  }, []);

  const refreshConnection = useCallback(async () => {
    setConnection("CONNECTING");

    // A demo session has no server to talk to; re-probing it would only ever
    // produce a misleading result.
    if (getStoredMode() === "demo" && !getToken()) {
      setConnection("OFFLINE");
      return;
    }

    // Health answers first, because retrying /auth/me against a dead API just
    // burns the request budget and reports the same failure twice.
    const reachable = await probeConnection();
    setConnection(reachable);

    const token = getToken();
    if (!token) {
      // Nothing to re-validate. A failed sign-in leaves no token, so recovering
      // connectivity simply hands the form back to the operator.
      if (!user) setPhase("unauthenticated");
      return;
    }

    // The token is still held from the failed handshake, so finish it properly
    // instead of leaving the workspace permanently stuck on the error screen.
    try {
      const me = await liveApi.me();
      clearDemoState();
      setStoredMode("live");
      setStoredDemoUser(null);
      setUser(me);
      setPhase("live-authenticated");
      setConnection("CONNECTED");
    } catch (error) {
      const status = statusOf(error);
      if (isRejectedSession(status)) {
        setToken(null);
        clearDemoState();
        setUser(null);
        setPhase("unauthenticated");
        return;
      }
      if (status === 0) setConnection("OFFLINE");
      setPhase({ kind: "live-error", reason: reasonFor(error) });
    }
  }, [user]);

  // ---------------------------------------------------------------------
  // Bootstrap state machine.
  //
  //   valid live token? -> /me -> live-authenticated
  //   no token          -> signed out
  //   explicit demo btn -> demo-preview
  //
  // Order matters and is the whole point: the live token is examined FIRST and
  // a stored demo marker is only consulted when there is no token at all. A
  // network fault during /me yields `live-error` and KEEPS the token, because
  // losing a good session to a flaky network is its own kind of lie.
  // ---------------------------------------------------------------------
  useEffect(() => {
    setUnauthorizedHandler(logout);
    let cancelled = false;

    const settle = (next: AuthPhase, nextUser: UserMe | null) => {
      if (cancelled) return;
      setPhase(next);
      setUser(nextUser);
    };

    const token = getToken();

    if (token) {
      setConnection("CONNECTING");
      liveApi
        .me()
        .then((me) => {
          // A real identity is authoritative: discard every demo marker so a
          // later reload cannot resurrect the synthetic workspace.
          clearDemoState();
          settle("live-authenticated", me);
          setConnection("CONNECTED");
        })
        .catch((error: unknown) => {
          const status = statusOf(error);
          if (isRejectedSession(status)) {
            // A definitive rejection. The token is genuinely dead.
            setToken(null);
            clearDemoState();
            settle("unauthenticated", null);
            return;
          }
          // Transport-level failure. Stay live, keep the token, offer Retry.
          if (status === 0) setConnection("OFFLINE");
          settle({ kind: "live-error", reason: reasonFor(error) }, null);
        });
      return () => {
        cancelled = true;
        setUnauthorizedHandler(null);
      };
    }

    // No live token. Only now may a demo marker be honoured.
    if (getStoredMode() === "demo") {
      try {
        const raw = getStoredDemoUser();
        const parsed = raw ? (JSON.parse(raw) as UserMe) : null;
        const role = parsed?.role || "beekeeper";
        const restored = resetDemo(role);
        if (parsed) setDemoUser(parsed);
        settle("demo-preview", parsed || restored);
      } catch {
        clearDemoState();
        settle("unauthenticated", null);
      }
    } else {
      settle("unauthenticated", null);
    }

    setConnection("CONNECTING");
    void probeConnection().then((state) => {
      if (!cancelled) setConnection(state);
    });

    return () => {
      cancelled = true;
      setUnauthorizedHandler(null);
    };
  }, [logout]);

  const value = useMemo<AuthState>(() => {
    const mode = modeFor(phase);
    return {
      user,
      phase,
      loading: phase === "live-authenticating",
      mode,
      api: mode === "demo" ? demoApi : liveApi,
      connection,
      logout,
      refreshConnection,
      login: async (identifier, password) => {
        // A live login attempt always starts clean: no leftover demo identity,
        // no stale token.
        clearDemoState();
        setPhase("live-authenticating");

        try {
          const token = await liveApi.login(identifier, password);
          setToken(token.access_token);

          const me = await liveApi.me();
          setStoredMode("live");
          setStoredDemoUser(null);
          setUser(me);
          setPhase("live-authenticated");
          setConnection("CONNECTED");
          return me;
        } catch (error) {
          const status = statusOf(error);

          if (isDefinitive(status)) {
            // The request itself was rejected: bad credentials, a malformed
            // field, or a token that is already dead. Retrying cannot help, so
            // the form stays available and nothing is kept. A 429 is excluded
            // because waiting and retrying genuinely can.
            setToken(null);
            setUser(null);
            setPhase("unauthenticated");
          } else {
            // Unreachable, or the server failed. No session exists to keep, so
            // stay in the live world and report the fault. Falling back to a
            // demo workspace here is exactly the behaviour this portal forbids.
            if (status === 0) setConnection("OFFLINE");
            setUser(null);
            setPhase({ kind: "live-error", reason: reasonFor(error) });
          }
          throw error;
        }
      },
      enterDemo: (role) => {
        // The ONLY entry point into demo mode. Nothing in the failure path of
        // a live request calls this.
        resetDemo(role);
        const matched = demoUserForRole(role);
        setDemoUser(matched);
        setToken(null);
        setStoredMode("demo");
        setStoredDemoUser(JSON.stringify(matched));
        setUser(matched);
        setPhase("demo-preview");
        return matched;
      },
    };
  }, [user, phase, connection, logout, refreshConnection]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useHoneyAuth() {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("useHoneyAuth must be used within HoneyAuthProvider");
  return ctx;
}

export { homeForRole };
export type { AuthPhase };
