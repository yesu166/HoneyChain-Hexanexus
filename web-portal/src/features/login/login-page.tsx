import { Link, Navigate, useNavigate } from "@tanstack/react-router";
import { Hexagon } from "lucide-react";
import { useState } from "react";
import { useHoneyAuth } from "@/lib/hc/auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { apiOrigin, describeApiError } from "@/lib/hc/client";

export function LoginPage() {
  const { user, login, loading, connection, refreshConnection } = useHoneyAuth();
  const navigate = useNavigate();
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

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

      <p className="mt-8 text-center text-xs leading-5 text-muted">
        Looking to try the sample workflows? Return to the HoneyChain homepage and choose a supply-chain demo.
      </p>
    </div>
  );
}
