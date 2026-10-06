import { Link } from "@tanstack/react-router";
import { ArrowRight, Lock, ScanLine } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/hc/page-header";
import { HeroStatus } from "@/components/hc/kpi";
import { useHoneyAuth } from "@/lib/hc/auth";
import { roleLabel, homeForRole } from "@/lib/hc/format";
import { apiOrigin } from "@/lib/hc/client";
import type { Role } from "@/lib/hc/types";
import {
  WORKSPACES,
  WORKSPACE_GROUPS,
  workspaceAvailability,
  workspacePathFor,
  type Workspace,
  type WorkspaceAvailability,
} from "@/lib/hc/workspaces";

/**
 * The HoneyChain workspace selector.
 *
 * One authenticated session lands here, and the operator chooses which part of
 * the platform to work in. This is a navigation screen, not an authorization
 * mechanism:
 *
 *   - The single live session is untouched. The JWT is still what the API
 *     checks, and nothing on this page grants, widens or simulates anything.
 *   - Availability is read from `user.role`, which HoneyChain returned in
 *     `/auth/me`. A workspace this identity may not open is shown as part of the
 *     platform and marked restricted, with no link to follow. There is no path
 *     from here that avoids a 403.
 *   - Demo is never a card here. A demo session is a different world with
 *     synthetic records, so it is not offered inside the live selector at all.
 */
function isRole(value: string | undefined): value is Role {
  return (
    value === "beekeeper" ||
    value === "fpo" ||
    value === "lab" ||
    value === "processor" ||
    value === "buyer" ||
    value === "admin" ||
    value === "institution" ||
    value === "platform_oversight"
  );
}

export function PortalSelector() {
  const { user, mode } = useHoneyAuth();

  // In demo the operator already picked a concrete preview identity, and the
  // platform selector would be a role switcher. Go straight to that workspace.
  if (mode === "demo") {
    return <DemoRedirectNotice />;
  }

  const role = user?.role;
  const roles: Role[] = user?.roles?.length
    ? user.roles
    : role && isRole(role)
      ? [role]
      : [];
  const openable = WORKSPACES.filter(
    (w) => workspaceAvailability(w, role, roles) === "available" || workspaceAvailability(w, role, roles) === "public",
  ).length;

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="HoneyChain"
        title="Choose a workspace"
        description="HoneyChain runs one traceability chain across every part of the honey economy. Pick the workspace that matches what you are here to do."
      />

      <HeroStatus
        tone={openable ? "ok" : "warn"}
        title={
          openable
            ? `Signed in as ${user?.name || roleLabel(role)} · ${roles.join(", ")}`
            : "Signed in, but no workspace is open to this account"
        }
        detail={`${openable} of ${WORKSPACES.length} HoneyChain surfaces are open in this portal. The rest sit outside the portal or need a role this account does not hold. Session verified against ${apiOrigin()}.`}
      />

      {/* The eight cards are grouped the way the product is actually organised:
          who governs, who makes the honey, where the field work happens, and
          what the public can reach without an account. Grouping is presentational
          only — availability still comes from `workspaceAvailability`. */}
      {WORKSPACE_GROUPS.map((group) => {
        const members = WORKSPACES.filter((workspace) => workspace.group === group);
        if (!members.length) return null;
        return (
          <section key={group}>
            <h2 className="mb-3 text-[11px] font-bold tracking-[0.16em] text-honey-600 uppercase">
              {group}
            </h2>
            <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
              {members.map((workspace) => (
                <WorkspaceCard key={workspace.id} workspace={workspace} role={role} roles={roles} />
              ))}
            </div>
          </section>
        );
      })}

      <Card className="border border-black/5">
        <p className="text-[11px] font-bold tracking-[0.16em] text-grove-700 uppercase">
          About access
        </p>
        <p className="mt-2 text-sm leading-6 text-muted">
          Workspaces you can open are decided by the role HoneyChain issued this account, not by
          anything chosen on this page. A workspace marked{" "}
          <span className="font-semibold text-ink">request access</span> is part of HoneyChain but
          is not granted to this account, so there is nothing to open yet. Ask a platform
          administrator to onboard the right role.
        </p>
      </Card>
    </div>
  );
}

function WorkspaceCard({
  workspace,
  role,
  roles,
}: {
  workspace: Workspace;
  role: string | undefined;
  roles: Role[];
}) {
  const availability = workspaceAvailability(workspace, role, roles);
  const path = workspacePathFor(workspace, role, roles);
  const Icon = workspace.icon;

  return (
    <WorkspaceTile
      icon={<Icon size={22} />}
      name={workspace.name}
      purpose={workspace.purpose}
      appCapabilities={workspace.appCapabilities ?? []}
      appDownloadUrl={workspace.appDownloadUrl}
      appAvailabilityNote={workspace.appAvailabilityNote ?? ""}
      availability={availability}
      unavailableNote={workspace.unavailableNote}
      requiredRoles={workspace.roles}
      to={path}
    />
  );
}

function WorkspaceTile({
  icon,
  name,
  purpose,
  appCapabilities,
  appDownloadUrl,
  appAvailabilityNote,
  availability,
  unavailableNote,
  requiredRoles,
  to,
}: {
  icon: React.ReactNode;
  name: string;
  purpose: string;
  /** Capabilities of an app surface; empty for every web workspace. */
  appCapabilities: string[];
  /** Real download URL for the app surface, when one is actually published. */
  appDownloadUrl?: string;
  /** Stated when no download URL is published; must stay factual. */
  appAvailabilityNote: string;
  availability: WorkspaceAvailability;
  unavailableNote?: string;
  requiredRoles: string[];
  to?: string;
}) {
  if (availability === "public") {
    // The consumer passport needs no account, so it is a plain link out of the
    // signed-in shell rather than a workspace this session holds.
    return (
      <Card className="flex h-full flex-col border border-grove-100">
        <div className="flex items-start justify-between gap-3">
          <div className="grid h-11 w-11 place-items-center rounded-2xl bg-grove-100 text-grove-800">
            {icon}
          </div>
          <Badge tone="info">No account needed</Badge>
        </div>
        <h2 className="mt-4 font-display text-xl text-ink">{name}</h2>
        <p className="mt-1 text-sm leading-6 text-muted">{purpose}</p>
        <div className="mt-4 pt-1">
          <Link
            to="/passport"
            search={{}}
            className="inline-flex min-h-11 items-center gap-2 rounded-xl bg-grove-700 px-4 text-sm font-semibold text-cream transition hover:bg-grove-800"
          >
            <ScanLine size={16} /> Open passport lookup
          </Link>
        </div>
      </Card>
    );
  }

  if (availability === "not-provisioned") {
    return (
      <Card className="flex h-full flex-col border border-dashed border-black/15 bg-black/[0.02]">
        <div className="flex items-start justify-between gap-3">
          <div className="grid h-11 w-11 place-items-center rounded-2xl bg-black/5 text-muted">
            {icon}
          </div>
          <Badge tone="warn">Not provisioned</Badge>
        </div>
        <h2 className="mt-4 font-display text-xl text-ink">{name}</h2>
        <p className="mt-1 text-sm leading-6 text-muted">{purpose}</p>
        <p className="mt-4 rounded-xl bg-honey-50 px-3 py-2 text-xs leading-5 text-honey-600">
          {unavailableNote}
        </p>
      </Card>
    );
  }

  // A surface delivered outside the portal is never a link and never a
  // "restricted" card: the account is not missing a permission, the work simply
  // happens somewhere else. What the app does is stated, and a download is
  // offered only if HoneyChain actually publishes one.
  if (availability === "app") {
    return (
      <Card className="flex h-full flex-col border border-black/5">
        <div className="flex items-start justify-between gap-3">
          <div className="grid h-11 w-11 place-items-center rounded-2xl bg-honey-100 text-honey-600">
            {icon}
          </div>
          <Badge tone="neutral" className="gap-1.5">
            Android app
          </Badge>
        </div>
        <h2 className="mt-4 font-display text-xl text-ink">{name}</h2>
        <p className="mt-1 text-sm leading-6 text-muted">{purpose}</p>
        {appCapabilities?.length ? (
          <ul className="mt-3 space-y-1.5 text-sm text-muted">
            {appCapabilities.map((capability) => (
              <li key={capability} className="flex gap-2">
                <span aria-hidden="true" className="text-honey-500">
                  •
                </span>
                <span>{capability}</span>
              </li>
            ))}
          </ul>
        ) : null}
        <p className="mt-4 rounded-xl bg-black/[0.03] px-3 py-2 text-xs leading-5 text-muted">
          {appDownloadUrl ? (
            <a
              href={appDownloadUrl}
              className="font-semibold text-grove-700 underline underline-offset-2"
              rel="noreferrer"
              target="_blank"
            >
              Download the Android build
            </a>
          ) : (
            appAvailabilityNote
          )}
        </p>
      </Card>
    );
  }

  if (availability === "restricted" || !to) {
    return (
      <Card className="flex h-full flex-col border border-dashed border-black/15 bg-black/[0.02]">
        <div className="flex items-start justify-between gap-3">
          <div className="grid h-11 w-11 place-items-center rounded-2xl bg-black/5 text-muted">
            {icon}
          </div>
          <Badge tone="neutral" className="gap-1.5">
            <Lock size={11} /> Request access
          </Badge>
        </div>
        <h2 className="mt-4 font-display text-xl text-ink">{name}</h2>
        <p className="mt-1 text-sm leading-6 text-muted">{purpose}</p>
        <p className="mt-4 rounded-xl bg-black/[0.03] px-3 py-2 text-xs leading-5 text-muted">
          Not granted to this account. It needs the{" "}
          <span className="font-semibold text-ink">
            {requiredRoles.map((r) => roleLabel(r)).join(" or ")}
          </span>{" "}
          role in HoneyChain, so there is nothing to open yet.
        </p>
      </Card>
    );
  }

  return (
    <Link
      to={to}
      className="group flex h-full flex-col rounded-2xl bg-paper p-5 shadow-[var(--shadow-card)] transition hover:-translate-y-0.5 hover:shadow-lg focus-visible:ring-2 focus-visible:ring-grove-700 focus-visible:outline-none"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="grid h-11 w-11 place-items-center rounded-2xl bg-honey-100 text-honey-600">
          {icon}
        </div>
        <Badge tone="ok">Open to you</Badge>
      </div>
      <h2 className="mt-4 font-display text-xl text-ink">{name}</h2>
      <p className="mt-1 text-sm leading-6 text-muted">{purpose}</p>
      <span className="mt-4 inline-flex items-center gap-1.5 pt-1 text-sm font-semibold text-grove-700">
        Open workspace
        <ArrowRight size={16} className="transition group-hover:translate-x-0.5" />
      </span>
    </Link>
  );
}

/**
 * Demo never enters the live selector, so a demo session that reaches this route
 * is sent to the preview workspace it chose, with a banner that says why.
 */
function DemoRedirectNotice() {
  const { user } = useHoneyAuth();
  // The demo identity's own workspace, not a hard-coded beekeeper path. A demo
  // operator who chose the laboratory preview was previously dumped into the
  // beekeeper workspace, which is both wrong and a form of the fake role
  // switching this selector exists to avoid.
  const demoHome = homeForRole(user?.role);
  return (
    <Card>
      <p className="text-[11px] font-bold tracking-[0.16em] text-honey-600 uppercase">
        Demo / preview
      </p>
      <h1 className="mt-2 font-display text-2xl text-ink">The workspace selector is a live screen</h1>
      <p className="mt-2 text-sm leading-6 text-muted">
        This is a demo session showing synthetic records, so the HoneyChain workspace selector is
        not offered here. In a live session it lists every HoneyChain workspace and marks the ones
        your account may open.
      </p>
      <Link
        to={demoHome}
        className="mt-4 inline-flex min-h-11 items-center gap-2 rounded-xl bg-honey-400 px-4 text-sm font-semibold text-ink"
      >
        Return to the demo workspace
      </Link>
    </Card>
  );
}
