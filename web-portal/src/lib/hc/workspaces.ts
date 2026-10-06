import {
  Building2,
  ClipboardCheck,
  Factory,
  Hexagon,
  Landmark,
  PackageCheck,
  ScanLine,
  ShieldCheck,
  Smartphone,
  type LucideIcon,
} from "lucide-react";
import type { AppPath } from "./nav";
import type { Role } from "./types";

/**
 * The HoneyChain platform, described once.
 *
 * This catalog is deliberately a *product* description, not a permission list.
 * It holds exactly eight cards in four groups — six operator personas plus the
 * two surfaces that exist outside the portal's login (the beekeeper mobile app
 * and the public Honey Passport) — whether or not the account that happens to
 * be signed in is allowed into all of them, so the selector shows the whole
 * platform and states plainly which parts this identity can open.
 *
 * Two rules keep it honest:
 *
 *   1. Availability is decided ONLY by `user.role`, which comes from the
 *      authoritative `GET /auth/me`. Nothing here grants access, and a card that
 *      is marked unavailable does not link anywhere, so a 403 cannot be walked
 *      around by clicking harder.
 *   2. A surface that is not a web workspace says so in words. The beekeeper
 *      card describes the mobile app instead of publishing a web route, and the
 *      public Honey Passport needs no account at all. Nothing here invents a
 *      workspace the API cannot gate.
 *
 * Market Linkage, the QR clone/reuse detector, the mobile processing van,
 * genealogy and blockchain are CAPABILITIES of these surfaces, not surfaces of
 * their own. They live on the FPO/Buyer, Processor, KVIC Field Officer and
 * Batch Detail screens respectively, and must never appear here as separate
 * portals. Market linkage is a tab in the FPO workspace and the whole Buyer
 * workspace; QR package identity and reuse detection is a panel on the
 * Processor workspace; the mobile processing van is a submodule of the KVIC
 * Field Officer screen. Each is backed by a real API and persisted rows — none
 * is a client-side simulation.
 */
export type WorkspaceId =
  | "kvic-admin"
  | "kvic-field-officer"
  | "lab-inspector"
  | "fpo"
  | "processor"
  | "buyer"
  | "beekeeper"
  | "consumer";

/**
 * The four selector groups. Ordered Government Operations → Supply Chain →
 * Mobile → Public: who governs, who makes the honey, where the field work
 * happens, and what the public can see without an account.
 */
export type WorkspaceGroup =
  | "Government Operations"
  | "Supply Chain"
  | "Mobile"
  | "Public";

export const WORKSPACE_GROUPS: WorkspaceGroup[] = [
  "Government Operations",
  "Supply Chain",
  "Mobile",
  "Public",
];

export type Workspace = {
  id: WorkspaceId;
  /** Which selector group this surface belongs to. */
  group: WorkspaceGroup;
  /** The name HoneyChain uses for this part of the platform. */
  name: string;
  /** One line on what the workspace is for. */
  purpose: string;
  icon: LucideIcon;
  /**
   * Backend roles that may open this workspace. Empty for a public workspace,
   * and deliberately absent for a surface that is not reached through the web.
   */
  roles: Role[];
  /**
   * Where to go when the identity is allowed in. Absent for a public workspace
   * reached by its own route, or for a surface served outside the portal.
   */
  path?: AppPath;
  /**
   * Some roles land on a different screen of the same workspace. The
   * `platform_oversight` role still exists in the backend RBAC matrix (it owns
   * organization and membership governance, and is withheld domain
   * administration), so it is routed to the platform tab it is actually
   * entitled to rather than being handed a card of its own.
   */
  pathForRole?: (role: Role) => AppPath | undefined;
  /** Reachable without any account at all. */
  public?: boolean;
  /**
   * A surface delivered outside the web portal. The catalog still describes it
   * because it is part of the product, but it never links to a web workspace.
   */
  surface?: "app";
  /** What the app surface actually does. Rendered verbatim on the card. */
  appCapabilities?: string[];
  /** Where the Android build can be obtained — only set when a URL is real. */
  appDownloadUrl?: string;
  /** Stated when no download URL is published yet. Must stay factual. */
  appAvailabilityNote?: string;
  /** False when the backend has no role and no endpoints for this workspace. */
  provisioned: boolean;
  /** Shown when `provisioned` is false. Must stay factual. */
  unavailableNote?: string;
};

/**
 * Ordered to match the physical chain of custody, hive to home, with the two
 * platform surfaces and the consumer surface at the end.
 */
export const WORKSPACES: Workspace[] = [
  {
    id: "kvic-admin",
    group: "Government Operations",
    name: "KVIC Admin",
    purpose:
      "Government operations for HoneyChain: cluster oversight, business operations, platform governance, and the risk & alerts view.",
    icon: ShieldCheck,
    roles: ["admin", "platform_oversight"],
    path: "/admin",
    // `platform_oversight` owns organization and membership governance but is
    // deliberately denied domain administration, so `/admin` would 403 for it.
    // It is routed to the platform tab it is actually entitled to.
    pathForRole: (role) => (role === "platform_oversight" ? "/admin/platform" : "/admin"),
    provisioned: true,
  },
  {
    id: "kvic-field-officer",
    group: "Government Operations",
    name: "KVIC Field Officer",
    purpose:
      "Field operations for a cluster: mobile processing van visits, sample intake, and issues needing institutional attention.",
    icon: Landmark,
    roles: ["institution", "admin", "platform_oversight"],
    path: "/kvic",
    provisioned: true,
  },
  {
    id: "lab-inspector",
    group: "Government Operations",
    name: "Lab Inspector",
    purpose: "Laboratory queue → test → result → certificate for incoming samples.",
    icon: ClipboardCheck,
    roles: ["lab", "admin"],
    path: "/lab",
    provisioned: true,
  },
  {
    id: "fpo",
    group: "Supply Chain",
    name: "FPO / Collection Manager",
    purpose:
      "Today's work for a producer organization: collection, batch pipeline, verification, market linkage, devices.",
    icon: Building2,
    roles: ["fpo", "admin"],
    path: "/org",
    provisioned: true,
  },
  {
    id: "processor",
    group: "Supply Chain",
    name: "Processor",
    purpose: "Aggregation, splitting, packaging, and custody transfer for lots moving down the chain.",
    icon: Factory,
    roles: ["processor", "admin"],
    path: "/processor",
    provisioned: true,
  },
  {
    id: "buyer",
    group: "Supply Chain",
    name: "Buyer / Procurement",
    purpose: "Procurement view of available lots with their laboratory and ledger status.",
    icon: PackageCheck,
    roles: ["buyer", "admin"],
    path: "/buyer",
    provisioned: true,
  },
  {
    id: "beekeeper",
    group: "Mobile",
    name: "Beekeeper Mobile App",
    purpose:
      "Hives, conditions, harvests and the field record a batch starts from — recorded in the field on Android.",
    icon: Smartphone,
    roles: ["beekeeper", "admin"],
    // No web path on purpose: this surface is the Android app, not a portal
    // workspace. The backend beekeeper role and every endpoint behind it are
    // untouched — only the catalog stopped offering a generic Beekeeper web
    // workspace, which the product does not ship as a surface.
    surface: "app",
    appCapabilities: [
      "Register hives, conditions, harvests and field notes",
      "Record a harvest offline and sync when the connection returns",
      "Receive hive, laboratory and collection notifications",
      "Ask My Bee guidance grounded in this yard's own readings",
    ],
    // No download URL is published, so none is linked. The Android build is
    // produced by the repository's CI and shipped in its `releases/` folder;
    // claiming a link that does not resolve would be worse than saying so.
    appAvailabilityNote:
      "No public download URL is published yet. The Android build is produced by the HoneyChain repository's CI and shipped in its `releases/` folder.",
    provisioned: true,
  },
  {
    id: "consumer",
    group: "Public",
    name: "Consumer / Honey Passport",
    purpose: "Scan or enter a code to check a product passport. No account required.",
    icon: ScanLine,
    roles: [],
    public: true,
    provisioned: true,
  },
];

/** The route a workspace opens for this identity, or undefined if it may not. */
export function workspacePathFor(workspace: Workspace, role: Role | string | undefined, roles: Role[] = []): AppPath | undefined {
  const allRoles = roles.length > 0 ? roles : (role ? [role] : []);
  if (workspace.public) return undefined;
  if (workspace.surface === "app") return undefined;
  if (!workspace.provisioned) return undefined;
  if (workspace.pathForRole) {
    const matchingRole = allRoles.find((r) => workspace.roles.includes(r as Role));
    if (matchingRole) return workspace.pathForRole(matchingRole as Role);
    return undefined;
  }
  if (workspace.path && allRoles.some((r) => workspace.roles.includes(r as Role))) return workspace.path;
  return undefined;
}

export type WorkspaceAvailability =
  /** No account is needed at all. */
  | "public"
  /** A surface delivered outside the portal (the Android app), so no web link. */
  | "app"
  /** The backend has no role for this workspace, so nobody can open it yet. */
  | "not-provisioned"
  /** HoneyChain granted this identity the role behind the workspace. */
  | "available"
  /** HoneyChain did not grant this identity that role. */
  | "restricted";

/**
 * Whether this identity may open the workspace.
 *
 * This is a *description of the session*, never a grant: it reads the role
 * HoneyChain returned and nothing else. When it says `restricted`, the API is
 * still the authority — the workspace simply is not offered as a link.
 */
export function workspaceAvailability(
  workspace: Workspace,
  role: Role | string | undefined,
  roles: Role[] = [],
): WorkspaceAvailability {
  const allRoles = roles.length > 0 ? roles : (role ? [role] : []);
  if (workspace.public) return "public";
  if (workspace.surface === "app") return "app";
  if (!workspace.provisioned) return "not-provisioned";
  if (allRoles.some((r) => workspace.roles.includes(r as Role))) return "available";
  return "restricted";
}

/** Hexagon is the HoneyChain mark; kept here so the catalog owns its icons. */
export const WORKSPACE_BRAND_ICON = Hexagon;
