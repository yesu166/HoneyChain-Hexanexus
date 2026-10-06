/**
 * Honey Passport: subject parsing, the stable public verification URL, the
 * backend-backed public lookup, and the derived passport lifecycle.
 *
 * Security model (§8): the browser never trusts a passport object it received
 * from the Honey Yatra QR, a link, or localStorage. A scan resolves to an identifier, and
 * the identifier is resolved by HoneyChain (`GET /api/v1/passport/{subject_code}`,
 * public + rate limited). Anything the server does not return is shown as "not
 * recorded" — never invented.
 */
import { publicFetch } from "./client.ts";
import { publicEnv } from "./env.ts";
import type {
  PassportLifecycleState,
  PassportResponse,
  PassportSubject,
  SupplyChain,
} from "./types.ts";

/**
 * Parse whatever a camera or a human produced into a stable HoneyChain subject
 * code. Accepts the Flutter app's canonical `honeychain://` payloads, the web
 * verification URLs this portal issues, and a bare batch/passport code.
 */
export function extractPassportSubject(raw: string): PassportSubject | null {
  const input = (raw || "").trim();
  if (!input) return null;

  const scheme = /^honeychain:\/\/(trace|jar|product|passport)\/([^/?#\s]+)/i.exec(input);
  if (scheme) {
    const kind = scheme[1].toLowerCase();
    return {
      code: decodeURIComponent(scheme[2]),
      kind: kind === "trace" ? "product" : (kind as PassportSubject["kind"]),
    };
  }

  if (/^https?:\/\//i.test(input)) {
    try {
      const url = new URL(input);
      const parts = url.pathname.split("/").filter(Boolean);
      const marker = parts[0]?.toLowerCase();
      if (marker === "verify" || marker === "passport") {
        const code = parts[1] || url.searchParams.get("code") || "";
        if (code) return { code: decodeURIComponent(code), kind: "passport" };
      }
      const query = url.searchParams.get("code");
      if (query) return { code: query, kind: "passport" };
      const last = parts[parts.length - 1];
      if (last) return { code: decodeURIComponent(last), kind: "passport" };
    } catch {
      /* fall through to the bare-code path */
    }
  }

  // A handwritten batch code. Reject anything with whitespace or a slash so a
  // pasted sentence never becomes a lookup.
  if (/^[A-Za-z0-9._-]{2,64}$/.test(input)) return { code: input, kind: "batch" };
  return null;
}

/**
 * The public base URL this portal is served from. `VITE_PUBLIC_APP_URL` wins so
 * a QR printed by a staging build can point at the production domain; otherwise
 * the current origin is used (works on localhost, Vercel, and Netlify).
 */
export function publicAppBase(): string {
  const configured = publicEnv("VITE_PUBLIC_APP_URL");
  if (configured) return configured.replace(/\/$/, "");
  if (typeof window !== "undefined") return window.location.origin;
  return "";
}

/**
 * The exact string encoded into the Honey Yatra QR. It is a stable verification URL, never
 * the passport JSON — scanning it opens this portal, which then asks HoneyChain.
 */
export function passportVerifyUrl(code: string): string {
  return `${publicAppBase()}/verify/${encodeURIComponent(code)}`;
}

/** Public, unauthenticated passport lookup. */
export async function fetchPublicPassport(code: string): Promise<PassportResponse> {
  return publicFetch<PassportResponse>(`/api/v1/passport/${encodeURIComponent(code)}`);
}

export interface LifecycleInput {
  batchStatus?: string | null;
  trustTier?: string | null;
  chain?: SupplyChain | null;
  /** True only when the public endpoint actually answered for this code. */
  publiclyResolved: boolean;
}

/**
 * Passport lifecycle (§9). Derived, never stored: the backend schema has no
 * passport-status column, so a portal that printed "VERIFIED" for a batch nobody
 * verified would be lying. Optional stages stay optional — a route without a
 * laboratory is still publishable.
 */
export function passportLifecycle(input: LifecycleInput): {
  state: PassportLifecycleState;
  label: string;
  detail: string;
} {
  const status = (input.batchStatus || "").toLowerCase();
  const tier = (input.trustTier || "").toLowerCase();
  const chain = input.chain;
  const verified =
    ["lab_verified", "blockchain_anchored", "authority_verified"].includes(tier) ||
    Boolean(chain?.passportReadiness.verified);

  if (status === "recalled" || status === "rejected") {
    return {
      state: "REVOKED",
      label: "Revoked",
      detail: `The batch state is "${status}", so this passport is not offered as provenance.`,
    };
  }
  if (input.publiclyResolved && verified) {
    return {
      state: "PUBLISHED",
      label: "Published & verified",
      detail: "HoneyChain returned this passport publicly with a verification tier on record.",
    };
  }
  if (input.publiclyResolved) {
    return {
      state: "PUBLISHED",
      label: "Published",
      detail:
        "HoneyChain returns this passport, but no laboratory or ledger verification tier is on record yet.",
    };
  }
  if (verified) {
    return {
      state: "VERIFIED",
      label: "Verified",
      detail: "Verification is on record; the passport has not been fetched publicly yet.",
    };
  }
  if (chain && chain.operationalCompleted > 0) {
    return {
      state: "TRACEABILITY_READY",
      label: "Traceability ready",
      detail: "Records exist for this lot. No verification tier is recorded yet.",
    };
  }
  return {
    state: "DRAFT",
    label: "Draft",
    detail: "Only the batch registration exists so far.",
  };
}

/** Honest one-line ledger statement — never claims anchoring that is not there. */
export function anchorStatement(anchor?: { chain_status?: string; tx_hash?: string } | null): {
  anchored: boolean;
  label: string;
  tx?: string;
} {
  if (anchor?.chain_status === "anchored") {
    return { anchored: true, label: "Blockchain anchored", tx: anchor.tx_hash || undefined };
  }
  if (anchor?.chain_status === "pending") {
    return { anchored: false, label: "Anchoring pending" };
  }
  return { anchored: false, label: "Blockchain anchoring unavailable" };
}
