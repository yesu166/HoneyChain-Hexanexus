import { Link, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { Hexagon } from "lucide-react";
import { PublicHeader } from "@/components/hc/app-shell";
import { ProvenancePath } from "@/components/hc/timeline";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

export function LandingPage() {
  const [code, setCode] = useState("");
  const navigate = useNavigate();

  return (
    <div className="min-h-screen">
      <PublicHeader />
      <main className="mx-auto max-w-5xl px-4 pb-16 md:px-8">
        <section className="grid gap-10 py-10 md:grid-cols-[1.2fr_0.8fr] md:items-center md:py-16">
          <div>
            <p className="text-[11px] font-bold tracking-[0.18em] text-grove-700 uppercase">
              India honey traceability
            </p>
            <h1 className="mt-3 font-display text-4xl leading-[1.1] text-ink md:text-5xl">
              From hive to home, with a record you can check.
            </h1>
            <p className="mt-4 max-w-xl text-base leading-7 text-muted">
              HoneyChain is the operations workspace for KVIC, FPOs, beekeepers, laboratories,
              processors, and buyers. Consumers can look up a product passport without signing in.
            </p>
            <form
              className="mt-8 flex flex-col gap-2 sm:flex-row"
              onSubmit={(e) => {
                e.preventDefault();
                const next = code.trim();
                if (!next) return;
                void navigate({ to: "/passport", search: { code: next } });
              }}
            >
              <Input
                value={code}
                onChange={(e) => setCode(e.target.value)}
                placeholder="Enter batch or passport code"
                aria-label="Passport code"
              />
              <Button type="submit" className="sm:w-44">
                Look up product
              </Button>
            </form>
            <p className="mt-3 text-xs text-muted">
              Demo example: <button type="button" className="underline" onClick={() => setCode("HC-NIL-2408-01")}>HC-NIL-2408-01</button>
            </p>
          </div>
          <aside className="rounded-3xl bg-grove-800 p-6 text-cream shadow-[var(--shadow-card)]">
            <div className="flex items-center gap-3">
              <span className="grid h-12 w-12 place-items-center rounded-2xl bg-honey-400 text-grove-800">
                <Hexagon size={26} />
              </span>
              <div>
                <p className="text-xs tracking-[0.16em] uppercase text-white/60">Operators</p>
                <p className="font-display text-2xl">Role workspaces</p>
              </div>
            </div>
            <p className="mt-4 text-sm leading-6 text-white/75">
              Sign in with your HoneyChain account. If the live API is not connected, open the
              labeled demo workspace.
            </p>
            <Button className="mt-5 w-full bg-honey-400 text-ink hover:bg-honey-500" asChild>
              <Link to="/login">Sign in</Link>
            </Button>
          </aside>
        </section>
        <section className="rounded-3xl bg-paper p-5 shadow-[var(--shadow-card)] md:p-8">
          <p className="text-[11px] font-bold tracking-[0.16em] text-grove-700 uppercase">The journey</p>
          <h2 className="mt-2 font-display text-2xl">Every lot should be able to show its path.</h2>
          <div className="mt-5">
            <ProvenancePath current="Product" />
          </div>
        </section>
      </main>
    </div>
  );
}
