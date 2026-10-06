/**
 * Route tree integrity.
 *
 * The portal used to ship a `src/routes/retailer.tsx` that exported a React
 * component and never called `createFileRoute`, while `src/routeTree.gen.ts`
 * had been hand-edited to import a `Route` from it. Two things followed:
 *
 *   - `Route` was `undefined` in that module, so the hand-written
 *     `RetailerRouteImport.update(...)` would throw `TypeError` if it were ever
 *     evaluated, taking the whole route tree — every route, not just that one —
 *     down with it.
 *   - The very next `vite build` regenerated `routeTree.gen.ts` from the real
 *     route files, silently dropping `/retailer`, so production 404'd on a
 *     workspace the navigation and the workspace selector still advertised.
 *
 * Nothing caught it: the build does not evaluate the route tree, and a dead
 * link is not an error. These tests pin the three invariants that were missing.
 */
import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import { WORKSPACES, workspacePathFor } from "./workspaces.ts";
import { navForRole } from "./nav.ts";
import type { Role } from "./types.ts";

// This file lives at src/lib/hc/, so the repository root is three levels up.
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const ROUTES_DIR = join(ROOT, "src", "routes");
const GENERATED_TREE = join(ROOT, "src", "routeTree.gen.ts");

/** Every route module on disk, recursively. */
function routeFiles(dir = ROUTES_DIR): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) return routeFiles(full);
    return full.endsWith(".tsx") ? [full] : [];
  });
}

const files = routeFiles();
const sources = new Map(files.map((f) => [f, readFileSync(f, "utf8")]));

/** Paths declared with `createFileRoute("...")`, i.e. real, registered routes. */
const declaredPaths = new Map<string, string>();
for (const [file, source] of sources) {
  const match = /createFileRoute\(\s*"([^"]+)"\s*\)/.exec(source);
  if (match) declaredPaths.set(match[1], file);
}

const generated = readFileSync(GENERATED_TREE, "utf8");
const generatedPaths = new Set(
  [...generated.matchAll(/fullPath:\s*'([^']+)'/g)].map((m) => m[1]),
);

/** Route files as forward-slash paths relative to `src/routes`. */
const routeModulePaths = new Set(
  files.map((f) => f.slice(ROUTES_DIR.length + 1).replace(/\\/g, "/").replace(/\.tsx$/, "")),
);

/**
 * The URL a declared route id serves.
 *
 * `/_workspace` is a pathless layout, so its children are declared as
 * `/_workspace/kvic` but are reachable at `/kvic`. The layout itself is not a
 * URL and therefore has no full path in the generated tree.
 */
function fullPathFor(declaredId: string): string | null {
  if (declaredId === "/_workspace") return null;
  const stripped = declaredId.replace(/^\/_workspace(?=\/)/, "");
  return stripped || "/";
}

test("every route module registers itself with the router", () => {
  // __root.tsx uses createRootRoute, which is the documented root exception.
  const unregistered = [...sources.entries()]
    .filter(([file]) => !file.endsWith("__root.tsx"))
    .filter(([, source]) => !/createFileRoute\(\s*"/.test(source))
    .map(([file]) => file.slice(ROOT.length + 1).replace(/\\/g, "/"));

  assert.deepEqual(
    unregistered,
    [],
    "a file in src/routes that never calls createFileRoute is not a route. " +
      "It will be ignored by the generator, so the path it looks like it serves " +
      "will 404 in production.",
  );
});

test("every route module exports the Route the generator imports", () => {
  const offenders = [...sources]
    .filter(([file]) => !file.endsWith("__root.tsx"))
    .filter(([, source]) => !/export const Route\s*=/.test(source))
    .map(([file]) => file.slice(ROOT.length + 1).replace(/\\/g, "/"));

  // The generated tree does `import { Route as X } from './routes/y'`, so a
  // module without that export makes the whole tree throw on evaluation.
  assert.deepEqual(offenders, [], "every route module must export a `Route` binding");
});

test("the generated tree is not hand-edited away from the route files", () => {
  const missing = [...declaredPaths.keys()]
    .map((id) => ({ id, full: fullPathFor(id) }))
    .filter((r): r is { id: string; full: string } => r.full !== null)
    .filter((r) => !generatedPaths.has(r.full))
    .map((r) => `${r.id} (expects ${r.full})`);

  assert.deepEqual(
    missing,
    [],
    "these routes exist as files but are absent from src/routeTree.gen.ts. " +
      "The build regenerates that file, so the committed version will be " +
      "overwritten and these paths will 404 in production.",
  );
});

test("the generated tree references no route module that does not exist", () => {
  const imported = [...generated.matchAll(/from\s+'\.\/routes\/([^']+)'/g)].map((m) => m[1]);
  const dangling = imported.filter((rel) => !routeModulePaths.has(rel));

  assert.deepEqual(
    dangling,
    [],
    "src/routeTree.gen.ts imports a route module that is not on disk",
  );
});

/** Roles the backend RBAC matrix can issue. */
const ROLES: Role[] = [
  "beekeeper",
  "fpo",
  "lab",
  "processor",
  "buyer",
  "institution",
  "admin",
  "platform_oversight",
];

test("every navigation entry resolves to a real route", () => {
  const advertised = new Set<string>();
  for (const role of ROLES) {
    for (const item of navForRole(role)) advertised.add(item.to);
    for (const item of navForRole(role, [role])) advertised.add(item.to);
  }

  const dangling = [...advertised].filter((to) => !generatedPaths.has(to));
  assert.deepEqual(
    dangling,
    [],
    "navForRole offers a link the route tree does not serve, so the sidebar " +
      "leads to a 404",
  );
});

test("every workspace the portal can open resolves to a real route", () => {
  const dangling: string[] = [];
  for (const workspace of WORKSPACES) {
    for (const role of ROLES) {
      const path = workspacePathFor(workspace, role, [role]);
      if (path && !generatedPaths.has(path)) {
        dangling.push(`${workspace.id} -> ${path}`);
      }
    }
  }

  assert.deepEqual(
    dangling,
    [],
    "a provisioned workspace points at a path the route tree does not serve, " +
      "so the workspace selector links to a 404",
  );
});

test("every workspace the catalog advertises is described honestly", () => {
  // A workspace with no backend role behind it must not be marked provisioned,
  // because that publishes a link nothing can enforce. An app surface is the
  // other case: it is real and provisioned, but it lives outside the portal, so
  // it must publish no web path and must say what the app does instead.
  for (const workspace of WORKSPACES) {
    if (workspace.public) continue;
    if (workspace.surface === "app") {
      assert.ok(
        workspace.roles.length > 0,
        `${workspace.id} is an app surface, and it still sits behind a real backend role`,
      );
      assert.equal(
        workspace.path,
        undefined,
        `${workspace.id} is not a web workspace, so it must not publish a path`,
      );
      assert.equal(
        workspacePathFor(workspace, "admin", ["admin"]),
        undefined,
        `${workspace.id} must never be reachable as a portal link`,
      );
      assert.ok(
        workspace.appCapabilities && workspace.appCapabilities.length > 0,
        `${workspace.id} must list what the app actually does`,
      );
      assert.ok(
        workspace.appDownloadUrl || workspace.appAvailabilityNote,
        `${workspace.id} must say how to get the app — or that none is published yet`,
      );
      continue;
    }
    if (!workspace.provisioned) {
      assert.ok(
        workspace.unavailableNote,
        `${workspace.id} is not provisioned and must say why in words`,
      );
      assert.equal(
        workspace.path,
        undefined,
        `${workspace.id} is not provisioned, so it must not publish a path`,
      );
    } else {
      assert.ok(
        workspace.roles.length > 0,
        `${workspace.id} is provisioned, so it needs a backend role that can open it`,
      );
      assert.ok(
        workspace.path || workspace.pathForRole,
        `${workspace.id} is provisioned, so it needs a path to open`,
      );
    }
  }
});

/**
 * The locked product surface: eight cards in four groups, in this order.
 *
 * "Six personas" counts only the operator personas; the beekeeper app and the
 * public Honey Passport are product surfaces, not personas, and stay in the
 * catalog. Market Linkage, the QR clone/reuse detector, the mobile processing
 * van, genealogy and blockchain are CAPABILITIES of these cards and must never
 * be added here as portals of their own.
 */
const CATALOG = [
  { id: "kvic-admin", group: "Government Operations", name: "KVIC Admin" },
  { id: "kvic-field-officer", group: "Government Operations", name: "KVIC Field Officer" },
  { id: "lab-inspector", group: "Government Operations", name: "Lab Inspector" },
  { id: "fpo", group: "Supply Chain", name: "FPO / Collection Manager" },
  { id: "processor", group: "Supply Chain", name: "Processor" },
  { id: "buyer", group: "Supply Chain", name: "Buyer / Procurement" },
  { id: "beekeeper", group: "Mobile", name: "Beekeeper Mobile App" },
  { id: "consumer", group: "Public", name: "Consumer / Honey Passport" },
];

test("the catalog is exactly the locked eight-card, four-group surface", () => {
  assert.equal(WORKSPACES.length, 8, "the catalog holds exactly eight cards");
  assert.deepEqual(
    WORKSPACES.map((w) => ({ id: w.id, group: w.group, name: w.name })),
    CATALOG,
    "the catalog must stay the eight locked cards, grouped and ordered as agreed",
  );

  // Surfaces the product deliberately retired: generic role cards and the
  // retailer workspace the backend has no role for.
  const removed = ["retailer", "platform-admin", "institution", "beekeeper-web", "platform-oversight"];
  for (const id of removed) {
    assert.equal(
      WORKSPACES.some((w) => w.id === id),
      false,
      `${id} must not return to the catalog`,
    );
  }

  // A capability must never grow into a portal.
  const notASurface = ["market", "qr", "van", "genealogy", "blockchain"];
  for (const workspace of WORKSPACES) {
    const name = workspace.name.toLowerCase();
    for (const capability of notASurface) {
      assert.equal(
        name.includes(capability),
        false,
        `"${workspace.name}" reads as a ${capability} portal; that is a capability of an existing surface`,
      );
    }
  }
});
