import type { AppPath } from "./nav";
import type { Batch, HealthScore, Role } from "./types";

/**
 * The single definition of a device that needs no attention.
 *
 * Three screens previously carried their own copy of this list and one of them
 * included "active" while the others did not, so the same sensor was flagged
 * unhealthy on the organization dashboard and healthy on the cluster page.
 *
 * "connected" is accepted alongside "online" because the backend uses both
 * spellings, and it is still not a claim about honey quality.
 */
const HEALTHY_DEVICE_STATES = ["online", "connected", "ok", "healthy", "active"];

export function isDeviceHealthy(status?: string | null): boolean {
  return HEALTHY_DEVICE_STATES.includes((status || "").toLowerCase());
}

export function fmtNum(value: number | null | undefined, suffix = ""): string {
  if (value === null || value === undefined || Number.isNaN(value)) {
    return "Not available";
  }
  return `${value.toLocaleString()}${suffix}`;
}

export function fmtDate(value?: string | null): string {
  if (!value) return "Not available";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "Not available";
  return d.toLocaleString(undefined, {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function fmtDay(value?: string | null): string {
  if (!value) return "Not available";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "Not available";
  return d.toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" });
}

export function trustLabel(tier?: string): string {
  switch (tier) {
    case "self_declared":
      return "Self declared";
    case "organization_verified":
      return "Organization verified";
    case "lab_verified":
      return "Lab verified";
    case "authority_verified":
      return "Authority verified";
    case "blockchain_anchored":
      return "Blockchain anchored";
    default:
      return tier ? tier.split("_").join(" ") : "Not available";
  }
}

export function roleLabel(role?: Role | string): string {
  switch (role) {
    case "institution":
      return "KVIC / Institution";
    case "fpo":
      return "FPO / Organization";
    case "beekeeper":
      return "Beekeeper";
    case "lab":
      return "Laboratory";
    case "processor":
      return "Processor";
    case "buyer":
      return "Buyer";
    case "admin":
      return "Platform admin";
    case "platform_oversight":
      return "Platform oversight";
    default:
      return role || "HoneyChain";
  }
}

export type Tone = "neutral" | "ok" | "warn" | "bad" | "info";

export function statusTone(value?: string | null): Tone {
  const v = (value || "").toLowerCase();
  if (
    ["active", "ok", "healthy", "passed", "pass", "verified", "confirmed", "anchored", "online"].some(
      (k) => v.includes(k),
    )
  ) {
    return "ok";
  }
  if (["pending", "requested", "in_progress", "attention", "medium", "stale", "warn"].some((k) => v.includes(k))) {
    return "warn";
  }
  if (["fail", "failed", "offline", "high", "critical", "unresolved", "revoked", "error"].some((k) => v.includes(k))) {
    return "bad";
  }
  return "neutral";
}

export function hiveRiskCopy(health: HealthScore): {
  title: string;
  detail: string;
  tone: Tone;
  next: string;
} {
  const level = health.risk_level.toLowerCase();
  if (level.includes("high") || health.risk_score >= 70) {
    return {
      title: "Attention recommended",
      detail: "This hive is showing conditions that need a visit soon.",
      tone: "bad",
      next: health.recommended_action || "Inspect the hive and record what you find.",
    };
  }
  if (level.includes("medium") || health.risk_score >= 40) {
    return {
      title: "Check this hive soon",
      detail: "A few readings are outside the usual range.",
      tone: "warn",
      next: health.recommended_action || "Walk the hive in the next inspection round.",
    };
  }
  return {
    title: "Hive looks stable",
    detail: "Temperature, humidity, and weight are within the usual range.",
    tone: "ok",
    next: health.recommended_action || "Continue regular inspection.",
  };
}

/**
 * The factual anchor status for a lot, in words that do not overclaim.
 *
 * This deliberately never renders the word "verified". A `chain_status` string
 * is only HoneyChain's opinion about an anchor; whether that anchor is worth
 * anything depends on the configured ledger adapter, and the current Render
 * deployment is the in-process development ledger. Screens that show this must
 * pair it with `readLedgerHealth()` so a local anchor is never dressed up as
 * tamper-evidence. See `anchorVerdict()` / `AnchorStatus` for that pairing.
 */
export function chainState(status?: string | null): { label: string; tone: Tone } {
  const s = (status || "").toLowerCase();
  if (!s || s === "none" || s === "unavailable" || s === "not_connected") {
    return { label: "No anchor reported", tone: "neutral" };
  }
  if (["anchored", "confirmed", "verified", "success"].some((k) => s.includes(k))) {
    return { label: "Anchored", tone: "ok" };
  }
  if (["pending", "submitted", "queued"].some((k) => s.includes(k))) {
    return { label: "Anchoring pending", tone: "warn" };
  }
  if (["fail", "error", "unable"].some((k) => s.includes(k))) {
    return { label: "Anchor failed", tone: "bad" };
  }
  return { label: "Anchor state unknown", tone: "neutral" };
}

/**
 * True only when the batch carries positive evidence of laboratory testing.
 *
 * This is deliberately conservative, because a false `true` becomes a
 * user-facing "Laboratory verified" claim on a lot nobody tested.
 *
 * Two traps this avoids:
 *
 *   - Substring matching on `status`. The backend has no reason to emit
 *     "unverified" or "not_verified", but if it ever did, `status.includes
 *     ("verified")` would report a lot as laboratory-verified. Statuses are
 *     therefore matched as whole tokens, and an explicitly negated one is
 *     rejected outright.
 *   - Letting `status` override `trust_tier`. A self-declared lot stays
 *     self-declared regardless of what its status string says.
 */
export function isLabVerified(batch: Pick<Batch, "trust_tier" | "lab_result" | "status">): boolean {
  const tier = (batch.trust_tier || "").toLowerCase();
  const result = (batch.lab_result || "").toUpperCase();

  // A recorded laboratory result is the strongest evidence available. Only an
  // explicit PASS counts; anything else, including an absent one, falls
  // through to the tier and status checks below.
  if (result === "PASS") return true;

  // A trust tier is authoritative and never negated by the status column.
  if (["lab_verified", "authority_verified", "blockchain_anchored"].includes(tier)) return true;
  if (tier === "self_declared") return false;

  const status = (batch.status || "").toLowerCase();
  // Whole-token match, so "unverified" cannot satisfy "verified".
  const tokens = status.split(/[^a-z0-9]+/).filter(Boolean);
  if (tokens.includes("unverified") || tokens.includes("notverified")) return false;
  if (tokens.includes("labverified") || tokens.includes("verified")) return true;

  return false;
}

export function packagingHint(batch: Batch): { allowed: boolean; reason: string } {
  if (isLabVerified(batch)) {
    return { allowed: true, reason: "Laboratory verification is on record." };
  }
  return {
    allowed: false,
    reason: "Packaging available after laboratory verification.",
  };
}

export function asString(value: unknown, fallback = "Not available"): string {
  if (typeof value === "string" && value.trim()) return value;
  if (typeof value === "number") return String(value);
  return fallback;
}

export function asNumber(value: unknown): number | undefined {
  if (typeof value === "number" && !Number.isNaN(value)) return value;
  if (typeof value === "string" && value.trim() && !Number.isNaN(Number(value))) {
    return Number(value);
  }
  return undefined;
}

export function homeForRole(role: Role | string | undefined): AppPath {
  switch (role) {
    case "institution":
      return "/kvic";
    case "fpo":
      return "/org";
    case "beekeeper":
      return "/beekeeper";
    case "lab":
      return "/lab";
    case "processor":
      return "/processor";
    case "buyer":
      return "/buyer";
    case "admin":
      return "/admin";
    case "platform_oversight":
      // Lands on the system view, which is the one place this role's
      // organization and membership permissions are actually exercised.
      return "/admin/platform";
    default:
      return "/passport";
  }
}
