import { Link, Navigate, createFileRoute, useRouterState } from "@tanstack/react-router";
import { CloudOff, RefreshCw } from "lucide-react";
import { AppShell } from "@/components/hc/app-shell";
import { Button } from "@/components/ui/button";
import { useHoneyAuth } from "@/lib/hc/auth";
import { isLiveError } from "@/lib/hc/auth-state";
import { apiOrigin, getToken } from "@/lib/hc/client";
import { allowedRolesForPath } from "@/lib/hc/nav";

export const Route = createFileRoute("/_workspace")({
  component: WorkspaceLayout,
});

/**
 * Shown when HoneyChain cannot be reached. It deliberately offers exactly two ways
 * out — retry, or sign in again. There is no "open the demo workspace" button
 * here: downgrading a live operator to synthetic data without being asked is
 * the failure mode this screen exists to prevent.
 */
function LiveErrorScreen({ reason }: { reason: string }) {
  const { logout, refreshConnection, connection } = useHoneyAuth();
  const checking = connection === "CONNECTING";

  // Read the real session rather than assuming one. Reaching this screen with
  // no token is normal after a failed sign-in, and claiming otherwise would be
  // the same class of lie the screen exists to prevent.
  const tokenHeld = Boolean(getToken());

  return (
    <div className="flex min-h-screen items-center justify-center bg-cream px-6">
      <div className="w-full max-w-md rounded-3xl bg-paper p-8 text-center shadow-[var(--shadow-card)]">
        <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl bg-honey-100 text-honey-600">
          <CloudOff size={26} />
        </div>
        <h1 className="mt-5 font-display text-2xl text-ink">HoneyChain is not responding</h1>
        <p className="mt-2 text-sm text-muted">
          {tokenHeld ? "Your session was kept." : "You are not signed in."} HoneyChain could not be
          reached because {reason}. No data was loaded, and nothing was switched to demo.
        </p>
        <p className="mt-3 break-all rounded-xl bg-cream px-3 py-2 text-[11px] text-muted">
          {apiOrigin()}
        </p>
        <div className="mt-6 flex flex-col gap-2">
          {tokenHeld ? (
            <Button onClick={() => void refreshConnection()} disabled={checking}>
              <RefreshCw size={16} className={checking ? "animate-spin" : undefined} />
              {checking ? "Checking…" : "Retry"}
            </Button>
          ) : null}
          <Button
            variant={tokenHeld ? "secondary" : "primary"}
            onClick={() => {
              logout();
              window.location.href = "/login";
            }}
          >
            {tokenHeld ? "Sign in again" : "Go to sign in"}
          </Button>
        </div>
        <p className="mt-5 text-[11px] text-muted">
          Looking for a product passport?{" "}
          <Link to="/passport" search={{}} className="text-grove-700 underline">
            Consumer verification needs no account
          </Link>
          .
        </p>
      </div>
    </div>
  );
}

function WorkspaceLayout() {
  const { user, phase, loading } = useHoneyAuth();
  const pathname = useRouterState({ select: (s) => s.location.pathname });

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-cream px-6">
        <div className="text-sm text-muted">Opening your HoneyChain workspace…</div>
      </div>
    );
  }

  // A live session whose API is unreachable keeps its token. Offer Retry here
  // rather than bouncing to the login screen or, worse, into demo data.
  if (isLiveError(phase)) return <LiveErrorScreen reason={phase.reason} />;

  if (!user) return <Navigate to="/login" />;

  const sessionRoles = user.roles?.length ? user.roles : [user.role];
  const allowed = allowedRolesForPath(pathname);
  if (allowed && !sessionRoles.some((role) => allowed.includes(role))) {
    // Someone typed or bookmarked a URL their role cannot open. Send them to
    // the selector, which shows the platform and marks what is unavailable,
    // rather than silently bouncing them to a home screen that gives no
    // explanation. This is a redirect, not a way in: the API still rejects the
    // original path.
    return <Navigate to="/portals" />;
  }

  return <AppShell />;
}
