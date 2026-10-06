import {
  Activity,
  Bell,
  ClipboardCheck,
  Factory,
  FileCheck2,
  Grid2x2,
  Hexagon,
  LayoutDashboard,
  Leaf,
  PackageCheck,
  ShieldCheck,
  Sparkles,
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
};

export function navForRole(role: Role | string | undefined, roles: Role[] = []): NavItem[] {
  // A live account may carry several HoneyChain workspace roles. Keep the
  // primary role as a backwards-compatible fallback, but build navigation
  // from every role the API issued rather than silently hiding workspaces.
  const allRoles = roles.length > 0 ? roles : role ? [role as Role] : [];
  const items: NavItem[] = [];
  const add = (candidate: NavItem[]) => {
    for (const item of candidate) {
      if (!items.some((existing) => existing.to === item.to)) items.push(item);
    }
  };

  for (const currentRole of allRoles) {
    switch (currentRole) {
      case "institution":
        add([
          { to: "/kvic", label: "Cluster status", icon: LayoutDashboard, group: "Overview" },
          { to: "/alerts", label: "Alerts", icon: Bell, group: "Monitoring" },
          { to: "/passport", label: "Product passport", icon: FileCheck2, group: "Traceability" },
        ]);
        break;
      case "fpo":
        add([
          { to: "/org", label: "Today", icon: LayoutDashboard, group: "Overview" },
          { to: "/alerts", label: "Alerts", icon: Bell, group: "Monitoring" },
          { to: "/ask-my-bee", label: "Ask My Bee", icon: Sparkles, group: "Guidance" },
        ]);
        break;
      case "beekeeper":
        add([
          { to: "/beekeeper", label: "My hives", icon: Leaf, group: "Overview" },
          { to: "/ask-my-bee", label: "Ask My Bee", icon: Sparkles, group: "Guidance" },
          { to: "/alerts", label: "Alerts", icon: Bell, group: "Monitoring" },
        ]);
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
        // Admin is the full-access operator account. Surface every existing
        // portal/workspace in navigation so the UI matches the server-side
        // admin permission set and does not hide capabilities the account can use.
        add([
          { to: "/admin", label: "Business ops", icon: ShieldCheck, group: "Business" },
          { to: "/kvic", label: "Clusters", icon: Hexagon, group: "Business" },
          { to: "/org", label: "FPO / Collection", icon: LayoutDashboard, group: "Supply chain" },
          { to: "/lab", label: "Laboratory", icon: ClipboardCheck, group: "Supply chain" },
          { to: "/processor", label: "Processor", icon: Factory, group: "Supply chain" },
          { to: "/buyer", label: "Buyer / Procurement", icon: PackageCheck, group: "Supply chain" },
          { to: "/beekeeper", label: "Beekeeper", icon: Leaf, group: "Field" },
          { to: "/ask-my-bee", label: "Ask My Bee", icon: Sparkles, group: "Field" },
          { to: "/passport", label: "Product passport", icon: FileCheck2, group: "Traceability" },
          { to: "/admin/platform", label: "Platform", icon: Activity, group: "System" },
          { to: "/alerts", label: "Alerts", icon: Bell, group: "System" },
        ]);
        break;
      case "platform_oversight":
        add([
          { to: "/admin/platform", label: "Platform", icon: Activity, group: "Oversight" },
          { to: "/kvic", label: "Clusters", icon: Hexagon, group: "Oversight" },
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
 * must not appear in a demo session: a demo identity is a single synthetic
 * person, and offering the platform selector there would amount to switching
 * between demo roles, which is exactly the fake role switching the portal
 * refuses to offer.
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
  if (pathname.startsWith("/beekeeper")) return ["beekeeper", "admin"];
  if (pathname.startsWith("/lab")) return ["lab", "admin"];
  if (pathname.startsWith("/processor")) return ["processor", "admin"];
  if (pathname.startsWith("/buyer")) return ["buyer", "admin"];
  // `platform_oversight` reaches the platform tab only. The business tab is
  // admin's, and this role holds `platform.stats` but not the domain actions
  // that screen is built around.
  if (pathname.startsWith("/admin/platform")) return ["admin", "platform_oversight"];
  if (pathname.startsWith("/admin")) return ["admin"];
  if (pathname.startsWith("/ask-my-bee")) return ["beekeeper", "fpo", "admin"];
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
