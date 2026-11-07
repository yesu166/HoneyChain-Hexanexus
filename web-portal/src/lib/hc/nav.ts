import {
  Activity,
  Bell,
  ClipboardCheck,
  Factory,
  FileCheck2,
  Grid2x2,
  Hexagon,
  LayoutDashboard,
  PackageCheck,
  ShieldCheck,
  Truck,
  type LucideIcon,
} from "lucide-react";
import type { Role } from "./types";

export type AppPath =
  | "/portals"
  | "/kvic"
  | "/alerts"
  | "/passport"
  | "/org"
  | "/ask-my-bee"
  | "/beekeeper"
  | "/lab"
  | "/processor"
  | "/buyer"
  | "/admin"
  | "/admin/platform";

export type NavItem = {
  to: AppPath;
  label: string;
  icon: LucideIcon;
  group: string;
  /** Optional in-page destination. */
  hash?: string;
};

export function navForRole(role: Role | string | undefined, roles: Role[] = []): NavItem[] {
  // A live account may carry several HoneyChain workspace roles. Keep the
  // primary role as a backwards-compatible fallback, but build navigation
  // from every role the API issued rather than silently hiding workspaces.
  const allRoles = roles.length > 0 ? roles : role ? [role as Role] : [];
  const items: NavItem[] = [];
  const add = (candidate: NavItem[]) => {
    for (const item of candidate) {
      if (!items.some((existing) => existing.to === item.to && existing.hash === item.hash)) items.push(item);
    }
  };

  for (const currentRole of allRoles) {
    switch (currentRole) {
      case "institution":
        add([
          { to: "/kvic", label: "Cluster overview", icon: LayoutDashboard, group: "Government operations" },
          { to: "/kvic", hash: "van-operations", label: "Mobile VAN operations", icon: Truck, group: "Government operations" },
          { to: "/kvic", hash: "lab-oversight", label: "Laboratory oversight", icon: ClipboardCheck, group: "Government operations" },
          { to: "/alerts", label: "Alerts", icon: Bell, group: "Monitoring" },
          { to: "/passport", label: "Product passport", icon: FileCheck2, group: "Traceability" },
        ]);
        break;
      case "fpo":
        add([
          { to: "/org", label: "Today", icon: LayoutDashboard, group: "Overview" },
          { to: "/alerts", label: "Alerts", icon: Bell, group: "Monitoring" },
        ]);
        break;
      // Beekeepers use the separate offline-first Flutter app. This web
      // portal exposes supply-chain operations, not a second beekeeper console.
      case "beekeeper":
        add([{ to: "/passport", label: "Product passport", icon: FileCheck2, group: "Traceability" }]);
        break;
      case "lab":
        add([
          { to: "/lab", label: "Test queue", icon: ClipboardCheck, group: "Operations" },
          { to: "/passport", label: "Product passport", icon: FileCheck2, group: "Traceability" },
        ]);
        break;
      case "processor":
        add([
          { to: "/processor", label: "Processing", icon: Factory, group: "Operations" },
          { to: "/alerts", label: "Alerts", icon: Bell, group: "Monitoring" },
        ]);
        break;
      case "buyer":
        add([
          { to: "/buyer", label: "Available lots", icon: PackageCheck, group: "Procurement" },
          { to: "/passport", label: "Product passport", icon: FileCheck2, group: "Traceability" },
        ]);
        break;
      case "admin":
        // Admin is the full-access online operator. Show the web supply-chain
        // and governance surfaces; offline beekeeper capture remains in Flutter.
        add([
          { to: "/admin", label: "Business ops", icon: ShieldCheck, group: "Business" },
          { to: "/kvic", label: "Cluster overview", icon: Hexagon, group: "Business" },
          { to: "/kvic", hash: "van-operations", label: "Mobile VAN operations", icon: Truck, group: "Business" },
          { to: "/kvic", hash: "lab-oversight", label: "Laboratory oversight", icon: ClipboardCheck, group: "Business" },
          { to: "/org", label: "FPO / Collection", icon: LayoutDashboard, group: "Supply chain" },
          { to: "/lab", label: "Laboratory", icon: ClipboardCheck, group: "Supply chain" },
          { to: "/processor", label: "Processor", icon: Factory, group: "Supply chain" },
          { to: "/buyer", label: "Buyer / Procurement", icon: PackageCheck, group: "Supply chain" },
          { to: "/passport", label: "Product passport", icon: FileCheck2, group: "Traceability" },
          { to: "/admin/platform", label: "Platform", icon: Activity, group: "System" },
          { to: "/alerts", label: "Alerts", icon: Bell, group: "System" },
        ]);
        break;
      case "platform_oversight":
        add([
          { to: "/admin/platform", label: "Platform", icon: Activity, group: "Oversight" },
          { to: "/kvic", label: "Cluster overview", icon: Hexagon, group: "Oversight" },
          { to: "/kvic", hash: "lab-oversight", label: "Laboratory oversight", icon: ClipboardCheck, group: "Oversight" },
          { to: "/alerts", label: "Alerts", icon: Bell, group: "Oversight" },
        ]);
        break;
      default:
        break;
    }
  }

  return items.length
    ? items
    : [{ to: "/passport", label: "Product passport", icon: FileCheck2, group: "Traceability" }];
}
/**
 * The link back to the HoneyChain workspace selector.
 *
 * It is returned separately from `navForRole` rather than inside it, because it
 * must not appear in a demo session. Demo role changes are an explicit action
 * from the public landing page; shared sample records are preserved and the
 * role-scoped query cache prevents one persona's rows leaking to another.
 * The authenticated selector remains a live-session navigation surface.
 */
export const WORKSPACE_SELECTOR_ITEM: NavItem = {
  to: "/portals",
  label: "All workspaces",
  icon: Grid2x2,
  group: "HoneyChain",
};

export function allowedRolesForPath(pathname: string): string[] | null {
  // The workspace selector is the authenticated landing screen. Every identity
  // with a session may open it, because its job is to show the platform and
  // say which parts this identity can enter. It reads `user.role` and grants
  // nothing, so it is not a way around any route below.
  if (pathname.startsWith("/portals")) {
    return [
      "beekeeper",
      "fpo",
      "lab",
      "processor",
      "buyer",
      "institution",
      "admin",
      "platform_oversight",
    ];
  }
  if (pathname.startsWith("/kvic")) return ["institution", "admin", "platform_oversight"];
  if (pathname.startsWith("/org")) return ["fpo", "admin"];
  // Legacy web routes stay registered for compatibility, but field capture and
  // voice-first Ask My Bee belong to the separate offline-first Flutter app.
  if (pathname.startsWith("/beekeeper")) return [];
  if (pathname.startsWith("/ask-my-bee")) return [];
  if (pathname.startsWith("/lab")) return ["lab", "admin"];
  if (pathname.startsWith("/processor")) return ["processor", "admin"];
  if (pathname.startsWith("/buyer")) return ["buyer", "admin"];
  // `platform_oversight` reaches the platform tab only. The business tab is
  // admin's, and this role holds `platform.stats` but not the domain actions
  // that screen is built around.
  if (pathname.startsWith("/admin/platform")) return ["admin", "platform_oversight"];
  if (pathname.startsWith("/admin")) return ["admin"];
  if (pathname.startsWith("/alerts")) {
    return [
      "beekeeper",
      "fpo",
      "lab",
      "processor",
      "buyer",
      "institution",
      "admin",
      "platform_oversight",
    ];
  }
  if (pathname.startsWith("/batches")) {
    return [
      "beekeeper",
      "fpo",
      "lab",
      "processor",
      "buyer",
      "institution",
      "admin",
      "platform_oversight",
    ];
  }
  return null;
}
