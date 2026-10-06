import { Link, Navigate, useNavigate } from "@tanstack/react-router";
import { Eye, Hexagon } from "lucide-react";
import { useState } from "react";
import { homeForRole, useHoneyAuth } from "@/lib/hc/auth";
import { DEMO_ROLES } from "@/lib/hc/demo";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { apiOrigin, describeApiError } from "@/lib/hc/client";

export function LoginPage() {
  const { user, login, enterDemo, loading, connection, refreshConnection } = useHoneyAuth();
  const navigate = useNavigate();
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [showPreview, setShowPreview] = useState(false);

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-cream text-sm text-muted">
        Checking your session…
      </div>
    );
  }
  if (user) return <Navigate to="/portals" />;

  return (
    <div className="mx-auto flex min-h-screen max-w-lg flex-col justify-center px-4 py-10">
      <div className="mb-6 flex items-center gap-3">
        <div className="grid h-12 w-12 place-items-center rounded-2xl bg-honey-400 text-grove-800">
          <Hexagon size={26} />
        </div>
        <div>
          <p className="font-display text-3xl leading-none text-grove-800">HoneyChain</p>
          <p className="mt-1 text-[11px] font-bold tracking-[0.15em] text-grove-700 uppercase">
            Welcome to HoneyChain
          </p>
        </div>
      </div>

      <p className="text-sm text-muted">
        One account, one identity. Signing in talks only to HoneyChain — a failed attempt
        reports the real reason and never opens a preview.
      </p>

      <form
        className="mt-6 space-y-4 rounded-3xl bg-paper p-6 shadow-[var(--shadow-card)]"
        onSubmit={async (e) => {
          e.preventDefault();
          setPending(true);
          setError(null);
          try {
            await login(identifier, password);
            // One HoneyChain login opens the workspace selector, not a role's
            // home screen. The session is already validated by the login call
            // itself (`/auth/login` then `/auth/me`), so there is no role to
            // pick here and nothing is assumed about which workspace this
            // account should land in.
            void navigate({ to: "/portals" });
          } catch (err) {
            // Real error, real status. No fallback path leaves this handler.
            setError(describeApiError(err).detail);
          } finally {
            setPending(false);
          }
        }}
      >
        <Label>
          Email or ID
          <Input
            className="mt-1"
            autoComplete="username"
            name="identifier"
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
          />
        </Label>
        <Label>
          Password
          <Input
            className="mt-1"
            type="password"
            autoComplete="current-password"
            name="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </Label>
        {error ? <p className="text-sm text-red-800">{error}</p> : null}
        <Button className="w-full" disabled={pending} type="submit">
          {pending ? "Signing in…" : "Sign in"}
        </Button>
      </form>

      <div className="mt-4 flex flex-wrap items-center gap-3 text-sm">
        <Link to="/passport" search={{}} className="text-grove-700 underline">
          Consumer passport — no account needed
        </Link>
        <span className="text-muted">·</span>
        <button
          type="button"
          className="text-muted underline disabled:opacity-60"
          disabled={connection === "CONNECTING"}
          onClick={() => void refreshConnection()}
        >
          {connection === "CONNECTING"
            ? "Checking HoneyChain…"
            : connection === "CONNECTED"
              ? "HoneyChain reachable"
              : "HoneyChain unreachable — retry"}
        </button>
      </div>

      {connection === "OFFLINE" ? (
        <p className="mt-2 break-all text-[11px] text-muted">
          No response from {apiOrigin()}. Signing in will report a connection error.
        </p>
      ) : null}

      {/* ---------------------------------------------------------------          Demo Workspace — deliberately OUTSIDE the live flow.
          It is reached only by this explicit button, it can never be entered
          by a failed request, and it sends nothing to the production API.
          --------------------------------------------------------------- */}
      <section className="mt-8 rounded-3xl border border-honey-200 bg-honey-50 p-5">
        <p className="flex items-center gap-2 text-[11px] font-bold tracking-[0.16em] text-honey-600 uppercase">
          <Eye size={13} /> Demo workspace
        </p>
        <h2 className="mt-1 font-display text-xl text-ink">Sample data, not HoneyChain records</h2>
        <p className="mt-2 text-sm text-muted">
          Sample records so the interface can be explored. Nothing here reaches the HoneyChain
          backend, and it is never shown to a signed-in live operator.
        </p>

        <Button
          type="button"
          variant="secondary"
          className="mt-4 w-full"
          onClick={() => setShowPreview((open) => !open)}
        >
          {showPreview ? "Hide demo roles" : "Choose a demo role"}
        </Button>

        {showPreview ? (
          <div className="mt-4 grid gap-2 sm:grid-cols-2">
            {DEMO_ROLES.map((item) => (
              <Button
                key={item.role}
                type="button"
                variant="secondary"
                onClick={() => {
                  const me = enterDemo(item.role);
                  void navigate({ to: homeForRole(me.role) });
                }}
              >
                {item.name}
              </Button>
            ))}
          </div>
        ) : null}
      </section>
    </div>
  );
}
