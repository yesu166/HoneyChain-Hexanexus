/**
 * Blockchain truth.
 *
 * HoneyChain is authoritative for what the ledger is, and the portal's only job is
 * to say exactly that and nothing more. Three rules are enforced here:
 *
 *   1. A ledger the backend calls `local` is NOT a blockchain. It is an
 *      in-process map used for development, and the UI must never present it as
 *      an anchor, a confirmation or a proof of anything.
 *   2. "Confirmed" is only ever printed when the backend reported a real
 *      transaction reference. The absence of a tx id is shown as such.
 *   3. `UNAVAILABLE` is a legitimate, expected state. It is never quietly
 *      upgraded to "verified", and it never triggers a switch to sample data.
 *
 * The adapter name decides the tier, because that is the field the backend
 * itself derives from `BLOCKCHAIN_ADAPTER`:
 *   fabric  -> a real Hyperledger Fabric network
 *   evm     -> an EVM chain
 *   local   -> the development/test in-process ledger ("simulated" is its
 *              legacy name in HoneyChain's config)
 */
import type { Tone } from "./format";

export type LedgerAdapter = "fabric" | "evm" | "local" | "unknown";

/**
 * What the UI is allowed to claim. `local` is called out explicitly so no
 * screen can accidentally render it as a distributed ledger.
 */
export type LedgerKind = "FABRIC" | "EVM" | "SIMULATED" | "LOCAL" | "UNAVAILABLE" | "UNKNOWN";

export type LedgerReachability =
  | "CONNECTED"
  | "NOT_CONFIGURED"
  | "MISCONFIGURED"
  | "UNAVAILABLE"
  | "UNKNOWN";

/** The raw `/api/v1/blockchain/health` payload, normalised. */
export interface LedgerHealth {
  adapter: LedgerAdapter;
  kind: LedgerKind;
  status: string;
  reachability: LedgerReachability;
  network: string;
  channel: string;
  chaincode: string;
  chaincodeVersion: string;
  chaincodeSequence: string;
  peer: string;
  mspId: string;
  lastVerifiedAt: string;
  error: string;
  /** True only for a real distributed ledger the backend actually reached. */
  distributed: boolean;
}

function text(value: unknown): string {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" || typeof value === "bigint") return String(value);
  return "";
}

export function normaliseAdapter(value: unknown): LedgerAdapter {
  const v = text(value).toLowerCase();
  if (v === "fabric" || v === "hyperledger") return "fabric";
  if (v === "evm" || v === "ethereum" || v === "polygon") return "evm";
  if (v === "local" || v === "simulated" || v === "memory") return "local";
  return "unknown";
}

export function kindForAdapter(adapter: LedgerAdapter): LedgerKind {
  switch (adapter) {
    case "fabric":
      return "FABRIC";
    case "evm":
      return "EVM";
    // HoneyChain calls the development ledger "simulated" in configuration and
    // "local" at runtime. Both mean the same thing to an operator.
    case "local":
      return "SIMULATED";
    default:
      return "UNAVAILABLE";
  }
}

function reachabilityFor(status: string, adapter: LedgerAdapter): LedgerReachability {
  const s = status.toLowerCase();
  if (s === "connected") return "CONNECTED";
  if (s.includes("not_configured")) return "NOT_CONFIGURED";
  if (s.includes("misconfigured")) return "MISCONFIGURED";
  if (s.includes("unavailable")) return "UNAVAILABLE";
  if (adapter === "local") return "CONNECTED";
  return "UNKNOWN";
}

/**
 * Build the honest view of the ledger from a backend payload.
 *
 * Accepts either `/blockchain/health` (flat) or the `fabric` sub-object nested
 * inside `/blockchain/status`, because HoneyChain uses both shapes depending on the
 * adapter.
 */
export function readLedgerHealth(payload: unknown): LedgerHealth {
  const root = (payload && typeof payload === "object" ? payload : {}) as Record<string, unknown>;
  const nested = (root.fabric && typeof root.fabric === "object" ? root.fabric : null) as
    | Record<string, unknown>
    | null;
  const src = nested ?? root;

  const adapter = normaliseAdapter(src.adapter ?? root.adapter);
  const status = text(src.status);
  const channel = text(src.channel);
  const chaincode = text(src.chaincode);
  const network = text(src.network) || channel;
  const reachability = reachabilityFor(status, adapter);
  const kind = kindForAdapter(adapter);

  return {
    adapter,
    kind,
    status,
    reachability,
    network,
    channel,
    chaincode,
    chaincodeVersion: text(src.chaincode_version),
    chaincodeSequence: text(src.chaincode_sequence),
    peer: text(src.peer),
    mspId: text(src.msp_id),
    lastVerifiedAt: text(src.last_verified_at),
    error: text(src.error),
    // A distributed ledger is one the backend actually reached over the
    // network. `local` never qualifies, however healthy it reports itself.
    distributed: kind === "FABRIC" || kind === "EVM" ? reachability === "CONNECTED" : false,
  };
}

export function ledgerHeadline(health: LedgerHealth | null): string {
  if (!health) return "Ledger status unavailable";
  switch (health.reachability) {
    case "CONNECTED":
      if (health.kind === "FABRIC") {
        return `Fabric connected — ${health.channel || "channel not reported"}${
          health.chaincode ? ` / ${health.chaincode}` : ""
        }`;
      }
      if (health.kind === "EVM") return `EVM connected — ${health.network || "network not reported"}`;
      return "Development ledger in use — not a distributed blockchain";
    case "NOT_CONFIGURED":
      return "Blockchain connection not configured";
    case "MISCONFIGURED":
      return "Blockchain gateway is misconfigured";
    case "UNAVAILABLE":
      return "Blockchain connection unavailable";
    default:
      return "Blockchain status unknown";
  }
}

export function ledgerTone(health: LedgerHealth | null): Tone {
  if (!health) return "neutral";
  if (health.reachability === "CONNECTED") {
    // A reachable development ledger is a working system, but it must read as
    // a warning so nobody mistakes it for a distributed one.
    return health.distributed ? "ok" : "warn";
  }
  if (health.reachability === "UNKNOWN") return "neutral";
  return "bad";
}

/**
 * The explanation shown next to the headline. It names the exact fact that
 * matters and never upgrades the claim.
 */
export function ledgerExplanation(health: LedgerHealth | null): string {
  if (!health) {
    return "HoneyChain did not return a ledger status. Nothing is claimed about the chain.";
  }
  if (health.error) return `Backend reported: ${health.error}`;

  if (!health.distributed) {
    if (health.adapter === "local") {
      return (
        "HoneyChain is configured with the in-process development ledger. Anchors produced by " +
        "this adapter are not written to any distributed network and prove nothing about " +
        "tamper-evidence. Switch BLOCKCHAIN_ADAPTER to fabric on the authoritative API to " +
        "anchor to Hyperledger Fabric."
      );
    }
    return (
      "This deployment is not backed by a distributed ledger, so no anchor, confirmation or " +
      "transaction reference can be shown."
    );
  }

  if (health.reachability !== "CONNECTED") {
    return `The Fabric gateway is not answering (${health.reachability.toLowerCase().replace(/_/g, " ")}). Existing anchors remain readable once it returns.`;
  }

  const parts = [
    `Channel ${health.channel || "not reported"}`,
    `chaincode ${health.chaincode || "not reported"}${
      health.chaincodeVersion ? ` v${health.chaincodeVersion}` : ""
    }`,
    `peer ${health.peer || "not reported"}`,
    `MSP ${health.mspId || "not reported"}`,
  ];
  return `Live query against ${parts.join(" · ")}.`;
}

/* ------------------------------------------------------------------ */
/* Anchors                                                             */
/* ------------------------------------------------------------------ */

export type AnchorVerdict = "ANCHORED" | "PENDING" | "FAILED" | "NOT_ANCHORED";

/**
 * The verdict for a single batch, derived only from the anchor row the backend
 * returned. A batch with no anchor row is `NOT_ANCHORED` — not "verified".
 */
export function anchorVerdict(anchor: {
  chain_status?: string;
  tx_hash?: string;
} | null | undefined): AnchorVerdict {
  const status = (anchor?.chain_status || "").toLowerCase();
  if (status === "anchored" && (anchor?.tx_hash || "").trim()) return "ANCHORED";
  if (status === "anchored") return "PENDING";
  if (["failed", "error", "rejected", "unknown"].includes(status)) return "FAILED";
  if (["pending", "submitted", "queued", "in_progress"].includes(status)) return "PENDING";
  return "NOT_ANCHORED";
}

/**
 * The badge for a batch that carries no anchor.
 *
 * `health === null` means the health request never answered, so this must not
 * claim that no ledger is configured — the deployment may well be on Fabric.
 * Callers that know the request failed should pass `unreadable` instead.
 */
export function anchorLabel(
  verdict: AnchorVerdict,
  health: LedgerHealth | null,
  unreadable = false,
): string {
  switch (verdict) {
    case "ANCHORED":
      return "Ledger anchor confirmed";
    case "PENDING":
      return "Anchoring pending";
    case "FAILED":
      return "Anchor failed";
    default:
      if (unreadable) return "Ledger status unknown";
      return health?.distributed
        ? "Not anchored to the ledger"
        : "No distributed ledger configured";
  }
}

export function anchorTone(verdict: AnchorVerdict): Tone {
  switch (verdict) {
    case "ANCHORED":
      return "ok";
    case "PENDING":
      return "warn";
    case "FAILED":
      return "bad";
    default:
      return "neutral";
  }
}

/**
 * The real Fabric transaction id, or an explicit statement that there is none.
 * Returns null rather than a placeholder so no caller can render a fabricated
 * reference.
 */
export function realTxId(anchor: { tx_hash?: string } | null | undefined): string | null {
  const tx = (anchor?.tx_hash || "").trim();
  return tx ? tx : null;
}
