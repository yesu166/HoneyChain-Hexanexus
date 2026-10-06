import { Link, Outlet, useRouterState } from "@tanstack/react-router";
import { Eye, Hexagon, LogOut, Menu } from "lucide-react";
import { useMemo, useState } from "react";
import { useHoneyAuth } from "@/lib/hc/auth";
import { roleLabel } from "@/lib/hc/format";
import { WORKSPACE_SELECTOR_ITEM, navForRole } from "@/lib/hc/nav";
import { apiOrigin } from "@/lib/hc/client";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent } from "@/components/ui/sheet";
import { cn } from "@/lib/utils";

function NavList({
  onNavigate,
  inverted = false,
}: {
  onNavigate?: () => void;
  inverted?: boolean;
}) {
  const { user, mode } = useHoneyAuth();
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const roleItems = navForRole(user?.role, user?.roles);
  // The selector belongs to a live session only. In demo it would be a role
  // switcher over one synthetic identity, so it is not offered there.
  // Derived inside the memo because `roleItems` is a fresh array each render and
  // `[WORKSPACE_SELECTOR_ITEM, ...roleItems]` would invalidate the groups map on
  // every single render.
  const groups = useMemo(() => {
    const items = mode === "demo" ? roleItems : [WORKSPACE_SELECTOR_ITEM, ...roleItems];
    const map = new Map<string, typeof items>();
    for (const item of items) {
      const list = map.get(item.group) || [];
      list.push(item);
      map.set(item.group, list);
    }
    return [...map.entries()];
  }, [mode, roleItems]);

  return (
    <nav className="flex-1 space-y-5 overflow-y-auto px-3 py-5">
      {groups.map(([group, groupItems]) => (
        <div key={group}>
          <p
            className={cn(
              "px-3 pb-2 text-[10px] font-bold tracking-[0.16em] uppercase",
              inverted ? "text-white/40" : "text-muted",
            )}
          >
            {group}
          </p>
          <div className="space-y-1">
            {groupItems.map((item) => {
              const Icon = item.icon;
              const active = pathname === item.to || pathname.startsWith(`${item.to}/`);
              return (
                <Link
                  key={item.to}
                  to={item.to}
                  onClick={onNavigate}
                  className={cn(
                    "flex min-h-11 items-center gap-3 rounded-xl px-3 text-sm font-semibold transition",
                    inverted
                      ? active
                        ? "bg-paper text-grove-800"
                        : "text-white/75 hover:bg-white/10 hover:text-white"
                      : active
                        ? "bg-grove-50 text-grove-800"
                        : "text-ink/70 hover:bg-black/5",
                  )}
                >
                  <Icon size={18} />
                  {item.label}
                </Link>
              );
            })}
          </div>
        </div>
      ))}
    </nav>
  );
}

function Brand() {
  return (
    <Link to="/" className="flex items-center gap-3">
      <div className="grid h-11 w-11 place-items-center rounded-2xl bg-honey-400 text-grove-800">
        <Hexagon size={22} strokeWidth={2.4} />
      </div>
      <div>
        <p className="font-display text-2xl leading-none">HoneyChain</p>
        <p className="mt-1 text-[11px] text-white/60">Hive to home traceability</p>
      </div>
    </Link>
  );
}

function ConnectionBadge() {
  const { mode, connection, refreshConnection } = useHoneyAuth();

  // Demo is a different world, so it gets its own unmistakable badge and never
  // borrows the live indicator.
  if (mode === "demo") {
    return (
      <Badge tone="demo" className="gap-1.5">
        <Eye size={12} />
        DEMO / PREVIEW
      </Badge>
    );
  }

  const label =
    connection === "CONNECTED"
      ? "LIVE API"
      : connection === "CONNECTING"
        ? "CONNECTING"
        : "OFFLINE";

  return (
    <button
      type="button"
      onClick={() => void refreshConnection()}
      title={
        connection === "OFFLINE"
          ? "HoneyChain is unreachable. Click to retry."
          : `Talking to ${apiOrigin()}`
      }
      className="rounded-full focus:outline-none focus-visible:ring-2 focus-visible:ring-grove-700"
    >
      <Badge
        tone={connection === "CONNECTED" ? "live" : connection === "CONNECTING" ? "warn" : "bad"}
        className="gap-1.5"
      >
        <span
          className={cn(
            "h-1.5 w-1.5 rounded-full",
            connection === "CONNECTED"
              ? "bg-honey-400"
              : connection === "CONNECTING"
                ? "animate-pulse bg-honey-600"
                : "bg-red-300",
          )}
        />
        {label}
      </Badge>
    </button>
  );
}

export function AppShell() {
  const { user, logout, mode } = useHoneyAuth();
  const [open, setOpen] = useState(false);
  const roleItems = navForRole(user?.role);
  // The selector belongs to a live session only. In demo it would be a role
  // switcher over one synthetic identity, so it is not offered there.
  const items = mode === "demo" ? roleItems : [WORKSPACE_SELECTOR_ITEM, ...roleItems];
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const current = items.find((item) => pathname === item.to || pathname.startsWith(`${item.to}/`));

  return (
    <div className="min-h-screen bg-cream md:grid md:grid-cols-[240px_1fr]">
      <aside className="hidden border-r border-black/5 bg-grove-800 text-cream md:flex md:flex-col">
        <div className="border-b border-white/10 px-5 py-6">
          <Brand />
        </div>
        <NavList inverted />
        <div className="border-t border-white/10 px-4 py-4">
          <div className="flex items-center gap-3 rounded-2xl bg-white/10 p-3">
            <div className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-honey-400 font-bold text-grove-800">
              {(user?.name || "H").slice(0, 1).toUpperCase()}
            </div>
            <div className="min-w-0">
              {/* The name is whatever HoneyChain returned in /auth/me, verbatim. */}
              <p className="truncate text-sm font-semibold text-white">{user?.name || "User"}</p>
              <p className="truncate text-[11px] text-white/50">{roleLabel(user?.role)}</p>
            </div>
          </div>
          <Button
            variant="ghost"
            className="mt-3 w-full justify-start text-white/70 hover:bg-white/10 hover:text-white"
            onClick={() => {
              logout();
              window.location.href = "/login";
            }}
          >
            <LogOut size={16} /> Sign out
          </Button>
        </div>
      </aside>

      <div className="flex min-h-screen min-w-0 flex-col">
        <header className="sticky top-0 z-30 flex items-center justify-between gap-3 border-b border-black/5 bg-cream/90 px-4 py-3 backdrop-blur-xl md:px-8">
          <div className="flex min-w-0 items-center gap-3">
            <Button
              variant="secondary"
              size="icon"
              className="md:hidden"
              aria-label="Open navigation"
              onClick={() => setOpen(true)}
            >
              <Menu size={18} />
            </Button>
            <div className="min-w-0">
              <p className="text-[10px] font-bold tracking-[0.16em] text-grove-700 uppercase">
                {roleLabel(user?.role)}
              </p>
              <p className="truncate text-sm font-semibold text-ink">{current?.label || "HoneyChain"}</p>
            </div>
          </div>
          <ConnectionBadge />
        </header>

        {mode === "demo" ? (
          <div className="flex flex-wrap items-center justify-center gap-x-2 gap-y-1 border-b border-honey-300 bg-honey-100 px-4 py-2 text-center text-xs font-semibold text-honey-600 md:px-8">
            <Eye size={13} />
            DEMO / PREVIEW — these records are synthetic and were never sent to HoneyChain.
          </div>
        ) : null}

        <main className="flex-1 px-4 py-6 pb-28 md:px-8 md:py-8 md:pb-10">
          <div className="mx-auto w-full max-w-[1280px]">
            <Outlet />
          </div>
        </main>

        <nav className="fixed inset-x-3 bottom-3 z-40 grid grid-cols-3 gap-1 rounded-2xl border border-black/5 bg-paper/95 p-1.5 shadow-[var(--shadow-card)] backdrop-blur-xl md:hidden">
          {/* The selector leads the sidebar, but on a phone the three most
              useful destinations are the workspace itself and the routes it is
              usually reached through, so the bar uses the role's own items and
              leaves the selector to the drawer. */}
          {(mode === "demo" ? roleItems : [...roleItems, WORKSPACE_SELECTOR_ITEM]).slice(0, 3).map((item) => {
            const Icon = item.icon;
            const active = pathname === item.to || pathname.startsWith(`${item.to}/`);
            return (
              <Link
                key={item.to}
                to={item.to}
                className={cn(
                  "flex min-h-12 min-w-0 flex-col items-center justify-center gap-1 rounded-xl px-1 text-[10px] font-semibold",
                  active ? "bg-honey-100 text-grove-800" : "text-muted",
                )}
              >
                <Icon size={17} />
                <span className="truncate">{item.label}</span>
              </Link>
            );
          })}
        </nav>

        <Sheet open={open} onOpenChange={setOpen}>
          <SheetContent>
            <div className="border-b border-white/10 px-5 py-6">
              <Brand />
            </div>
            <NavList inverted onNavigate={() => setOpen(false)} />
            <div className="p-4">
              <Button
                variant="ghost"
                className="w-full justify-start text-white/70 hover:bg-white/10 hover:text-white"
                onClick={() => {
                  logout();
                  window.location.href = "/login";
                }}
              >
                <LogOut size={16} /> Sign out
              </Button>
            </div>
          </SheetContent>
        </Sheet>
      </div>
    </div>
  );
}

export function PublicHeader() {
  const { user, mode } = useHoneyAuth();
  return (
    <header className="flex items-center justify-between gap-3 px-4 py-4 md:px-8">
      <Link to="/" className="flex items-center gap-2 text-grove-800">
        <span className="grid h-10 w-10 place-items-center rounded-xl bg-honey-400 text-grove-800">
          <Hexagon size={20} />
        </span>
        <span className="font-display text-xl">HoneyChain</span>
      </Link>
      <div className="flex items-center gap-2">
        {mode === "demo" ? <Badge tone="demo">Demo data</Badge> : null}
        <Button variant="secondary" asChild>
          <Link to="/passport" search={{}}>
            Passport
          </Link>
        </Button>
        {user ? (
          <Button asChild>
            {/* The selector, not a role's home screen: the product has nine
                workspaces and only the signed-in identity can say which of them
                it may open. */}
            <Link to="/portals">Workspaces</Link>
          </Button>
        ) : (
          <Button asChild>
            <Link to="/login">Sign in</Link>
          </Button>
        )}
      </div>
    </header>
  );
}
