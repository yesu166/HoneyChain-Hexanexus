import { ApiError } from "./types.ts";
import { isProductionBuild, publicEnv } from "./env.ts";

const TOKEN_KEY = "honeychain.jwt";
// Demo state is deliberately session-scoped, not browser-scoped.
//
// It used to live in localStorage, which meant a "demo" marker could survive for
// weeks and out-rank a perfectly valid live JWT on the next page load. Demo
// records are synthetic, so they have no business outliving the tab that asked
// for them; the live token keeps localStorage because a real session SHOULD
// survive a refresh.
const MODE_KEY = "honeychain.mode";
const DEMO_USER_KEY = "honeychain.demoUser";
// Bumped whenever the demo storage semantics change so a browser that already
// holds the old markers drops them once instead of reading them forever.
const DEMO_SCHEMA_KEY = "honeychain.demo.schema";
const DEMO_SCHEMA = "session-v1";

// Public deployment fallback only. VITE_API_BASE_URL remains the preferred
// environment-driven configuration; this prevents a production build from
// silently sending HoneyChain requests to the portal's own origin when a hosting
// dashboard has not supplied the public variable.
const PRODUCTION_API_ORIGIN = "https://honeychain-api.onrender.com";

/** Per-request budget. Allow the deployed API time to wake from a cold start. */
export const REQUEST_TIMEOUT_MS = 60_000;
/** One controlled retry, only for requests that are safe to repeat. */
export const RETRY_DELAY_MS = 600;

export function getToken(): string | null {
  if (typeof window === "undefined" || !("localStorage" in window)) return null;
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string | null) {
  if (typeof window === "undefined" || !("localStorage" in window)) return;
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
}

/**
 * Remove every trace of a demo session.
 *
 * Called whenever a real identity becomes authoritative, so a stale marker can
 * never be read again by a later page load.
 */
export function clearDemoState() {
  if (typeof window === "undefined") return;
  sessionStorage.removeItem(MODE_KEY);
  sessionStorage.removeItem(DEMO_USER_KEY);
  localStorage.removeItem(MODE_KEY);
  localStorage.removeItem(DEMO_USER_KEY);
}

function migrateDemoStorage() {
  if (typeof window === "undefined") return;
  if (sessionStorage.getItem(DEMO_SCHEMA_KEY) === DEMO_SCHEMA) return;
  // Pre-v1 builds wrote demo markers to localStorage. Evict them.
  localStorage.removeItem(MODE_KEY);
  localStorage.removeItem(DEMO_USER_KEY);
  sessionStorage.removeItem(MODE_KEY);
  sessionStorage.removeItem(DEMO_USER_KEY);
  sessionStorage.setItem(DEMO_SCHEMA_KEY, DEMO_SCHEMA);
}

export function getStoredMode(): "live" | "demo" {
  if (typeof window === "undefined") return "live";
  migrateDemoStorage();
  return sessionStorage.getItem(MODE_KEY) === "demo" ? "demo" : "live";
}

export function setStoredMode(mode: "live" | "demo") {
  if (typeof window === "undefined") return;
  migrateDemoStorage();
  if (mode === "demo") sessionStorage.setItem(MODE_KEY, mode);
  else clearDemoState();
}

export function getStoredDemoUser(): string | null {
  if (typeof window === "undefined") return null;
  migrateDemoStorage();
  return sessionStorage.getItem(DEMO_USER_KEY);
}

export function setStoredDemoUser(raw: string | null) {
  if (typeof window === "undefined") return;
  migrateDemoStorage();
  if (raw) sessionStorage.setItem(DEMO_USER_KEY, raw);
  else sessionStorage.removeItem(DEMO_USER_KEY);
}

export function apiBase(): string {
  const configured = publicEnv("VITE_API_BASE_URL");
  if (configured) return configured.replace(/\/$/, "");
  if (isProductionBuild()) return PRODUCTION_API_ORIGIN;
  return "";
}

/** The API origin the browser will actually call, for display and diagnostics. */
export function apiOrigin(): string {
  return apiBase() || (typeof window !== "undefined" ? window.location.origin : "");
}

let onUnauthorized: (() => void) | null = null;

export function setUnauthorizedHandler(handler: (() => void) | null) {
  onUnauthorized = handler;
}

/**
 * A production build must never call a developer machine. Returns a message
 * describing the misconfiguration, or null when the origin is acceptable.
 *
 * An empty `apiBase()` is fine: that is the same-origin deployment where the
 * host reverse-proxies `/api` to HoneyChain.
 */
export function apiOriginWarning(): string | null {
  const base = apiBase();
  if (!base) return null;
  if (!isProductionBuild()) return null;
  try {
    const { hostname, protocol } = new URL(base);
    if (hostname === "localhost" || hostname === "127.0.0.1" || hostname === "::1") {
      return (
        `This production build is configured to call ${base}. ` +
        "Set VITE_API_BASE_URL to the deployed HoneyChain API origin."
      );
    }
    if (protocol !== "https:") {
      return (
        `This production build calls ${base} over ${protocol.replace(":", "")}. ` +
        "A production HoneyChain API must be served over HTTPS."
      );
    }
  } catch {
    return `VITE_API_BASE_URL is not a valid URL: ${base}`;
  }
  return null;
}

let originWarned = false;

function warnOriginOnce(): void {
  if (originWarned) return;
  const warning = apiOriginWarning();
  if (!warning) return;
  originWarned = true;
  console.warn(`[honeychain] ${warning}`);
}

function abortError(url?: string): ApiError {
  return new ApiError(0, "The request to HoneyChain timed out.", "timeout", url);
}

function networkError(detail?: string, url?: string): ApiError {
  return new ApiError(0, detail || "Unable to connect. Please try again.", "network", url);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** GET/HEAD are safe to repeat; a POST must never be replayed by the transport. */
function isRetryable(init: RequestInit): boolean {
  const method = (init.method || "GET").toUpperCase();
  return method === "GET" || method === "HEAD";
}

/** 502/503/504 are gateway/transient states, not application errors. */
function isTransientStatus(status: number): boolean {
  return status === 502 || status === 503 || status === 504;
}

async function performFetch<T>(
  path: string,
  init: RequestInit,
  options: { auth: boolean },
): Promise<T> {
  warnOriginOnce();
  const retryable = isRetryable(init);
  let lastError: ApiError | null = null;

  // One controlled retry. Two attempts total — a bounded budget, not a loop.
  const url = `${apiBase()}${path}`;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    if (attempt > 0) await sleep(RETRY_DELAY_MS);

    const headers = new Headers(init.headers);
    if (!headers.has("Content-Type") && init.body) {
      headers.set("Content-Type", "application/json");
    }
    if (options.auth) {
      const token = getToken();
      if (token) headers.set("Authorization", `Bearer ${token}`);
    }

    const controller = new AbortController();
    // Honour a caller-supplied signal as well as our own deadline, so a
    // component unmount still cancels the request.
    const external = init.signal ?? null;
    const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    const onExternalAbort = () => controller.abort();
    external?.addEventListener("abort", onExternalAbort);

    let response: Response;
    try {
      response = await fetch(url, {
        ...init,
        headers,
        signal: controller.signal,
      });
    } catch (err) {
      const aborted =
        controller.signal.aborted ||
        (err instanceof Error && (err.name === "AbortError" || err.name === "TimeoutError"));
      lastError = aborted ? abortError(url) : networkError(undefined, url);
      if (retryable) continue;
      throw lastError;
    } finally {
      clearTimeout(timer);
      external?.removeEventListener("abort", onExternalAbort);
    }

    if (response.status === 401 && options.auth) {
      onUnauthorized?.();
      throw new ApiError(401, "Session expired. Please sign in again.", "http", url);
    }

    if (!response.ok) {
      let detail = defaultStatusMessage(response.status);
      try {
        const body = (await response.json()) as { detail?: unknown; message?: unknown };
        if (typeof body?.detail === "string") detail = body.detail;
        else if (typeof body?.message === "string") detail = body.message;
        else if (Array.isArray(body?.detail)) detail = "The request was rejected as invalid.";
      } catch {
        /* keep default */
      }
      if (retryable && isTransientStatus(response.status)) {
        lastError = new ApiError(response.status, detail, "http", url);
        continue;
      }
      throw new ApiError(response.status, detail, "http", url);
    }

    if (response.status === 204) return undefined as T;
    return (await response.json()) as T;
  }

  throw lastError ?? networkError(undefined, url);
}

export async function apiFetch<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  return performFetch<T>(path, init, { auth: true });
}

/**
 * Unauthenticated request for genuinely public HoneyChain surfaces (the consumer
 * passport and public certificate verification). It never attaches a token and
 * never triggers the sign-out handler: a consumer scanning a QR is not a
 * failing session.
 */
export async function publicFetch<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  return performFetch<T>(path, init, { auth: false });
}

function defaultStatusMessage(status: number): string {
  if (status === 403) return "This action requires a different HoneyChain role.";
  if (status === 404) return "This record was not found.";
  if (status === 408) return "The request timed out. Please try again.";
  if (status === 409) return "This record changed since you loaded it. Refresh and try again.";
  if (status === 422) return "HoneyChain rejected the request as invalid.";
  if (status === 429) return "Too many lookups. Please wait a moment and try again.";
  if (status >= 500) return "HoneyChain is unavailable right now.";
  return `Request failed (${status})`;
}

/**
 * Connectivity of the browser to the configured HoneyChain origin.
 *
 * `LIVE` is only reported after a real, successful round trip — never because a
 * build happens to contain a URL, and never because a demo session is active.
 */
export type ApiConnection = "CONNECTING" | "CONNECTED" | "OFFLINE";

export async function probeConnection(): Promise<ApiConnection> {
  try {
    await publicFetch<Record<string, unknown>>("/api/v1/health");
    return "CONNECTED";
  } catch {
    return "OFFLINE";
  }
}

function withRequestOrigin(detail: string, error: ApiError): string {
  if (!error.url) return detail;
  try {
    return `${detail} The request was sent to ${new URL(error.url).origin}.`;
  } catch {
    return detail;
  }
}

export function describeApiError(error: unknown): {
  title: string;
  detail: string;
  status: number;
} {
  if (error instanceof ApiError) {
    if (error.status === 0) {
      if (error.kind === "timeout") {
        return {
          title: "HoneyChain did not respond in time",
          detail: withRequestOrigin(
            "The HoneyChain API accepted the connection but did not answer. This is usually a cold start, not a missing record. Try again.",
            error,
          ),
          status: 0,
        };
      }
      return {
        title: "Unable to connect to HoneyChain",
        detail: withRequestOrigin(
          "The browser could not reach the HoneyChain API. Check the network, then retry. No data was loaded and nothing was switched to demo.",
          error,
        ),
        status: 0,
      };
    }
    if (error.status === 401) {
      return {
        title: "You need to sign in again",
        detail: "Your session expired.",
        status: 401,
      };
    }
    if (error.status === 403) {
      return {
        title: "This action requires a different role",
        detail: error.message || "Your HoneyChain role is not permitted to do this.",
        status: 403,
      };
    }
    if (error.status === 404) {
      return {
        title: "Not found",
        detail: withRequestOrigin(error.message || "This record is not in HoneyChain.", error),
        status: 404,
      };
    }
    if (error.status === 409) {
      return {
        title: "This record changed on the server",
        detail:
          error.message ||
          "Someone else updated this record (or it was already moved). Refresh to see the current HoneyChain state.",
        status: 409,
      };
    }
    if (error.status === 422) {
      return {
        title: "HoneyChain rejected the request",
        detail: error.message,
        status: 422,
      };
    }
    if (error.status === 429) {
      return {
        title: "Too many requests",
        detail: error.message,
        status: 429,
      };
    }
    if (error.status >= 500) {
      return {
        title: "HoneyChain is unavailable",
        detail: error.message,
        status: error.status,
      };
    }
    return {
      title: "Request could not be completed",
      detail: error.message,
      status: error.status,
    };
  }
  return {
    title: "Something went wrong",
    detail: error instanceof Error ? error.message : "Please try again.",
    status: 500,
  };
}
