import type { ReactNode } from "react";
import { useRouterState } from "@tanstack/react-router";
import { Badge } from "@/components/ui/badge";
import { useHoneyAuth } from "@/lib/hc/auth";

type FlowStep = { label: string };

function flowFor(pathname: string): FlowStep[] | null {
  if (pathname === "/kvic" || pathname.startsWith("/kvic/")) {
    return [{ label: "Review cluster status" }, { label: "Run VAN field visit" }, { label: "Review lab evidence" }];
  }
  if (pathname === "/lab") return [{ label: "Review sample queue" }, { label: "Run the test" }, { label: "Record the result" }];
  if (pathname === "/org") return [{ label: "Review collection" }, { label: "Create a batch" }, { label: "Connect to market" }];
  if (pathname === "/processor") return [{ label: "Receive an eligible lot" }, { label: "Package and label" }, { label: "Transfer custody" }];
  if (pathname === "/buyer") return [{ label: "Inspect eligible lots" }, { label: "Review evidence" }, { label: "Procure with context" }];
  if (pathname === "/admin/platform") return [{ label: "Review organizations" }, { label: "Check role governance" }, { label: "Inspect platform health" }];
  if (pathname === "/admin") return [{ label: "Business operations" }, { label: "Supply-chain status" }, { label: "Audit and alerts" }];
  if (pathname === "/alerts") return [{ label: "Review the alert" }, { label: "Open the related record" }, { label: "Track follow-up" }];
  if (pathname.startsWith("/batches/")) return [{ label: "Confirm origin" }, { label: "Review lab results" }, { label: "Follow custody" }];
  if (pathname === "/passport" || pathname.startsWith("/verify")) return [{ label: "Find the batch" }, { label: "Review recorded evidence" }, { label: "Check limitations" }];
  return null;
}

export function PageHeader({
  eyebrow,
  title,
  description,
  action,
}: {
  eyebrow?: string;
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  const { mode, connection } = useHoneyAuth();
  const pathname = useRouterState({ select: (state) => state.location.pathname });
  const steps = flowFor(pathname);
  const statusLabel =
    mode === "demo" ? "SAMPLE DATA" :
    connection === "CONNECTED" ? "LIVE API" :
    connection === "CONNECTING" ? "CHECKING API" : "API OFFLINE";
  const statusTone =
    mode === "demo" ? "demo" :
    connection === "CONNECTED" ? "live" :
    connection === "CONNECTING" ? "warn" : "bad";

  return (
    <section className="hc-page-heading mb-7">
      <header className="flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
        <div className="min-w-0">
          <div className="mb-3 flex flex-wrap items-center gap-2">
            {eyebrow ? <p className="text-[10px] font-bold tracking-[0.18em] text-grove-700 uppercase">{eyebrow}</p> : null}
            {eyebrow ? <span aria-hidden="true" className="h-1 w-1 rounded-full bg-honey-500" /> : null}
            <Badge tone={statusTone} className="gap-1.5">{statusLabel}</Badge>
          </div>
          <h1 className="font-display text-3xl leading-[1.08] tracking-tight text-ink md:text-[2.6rem]">{title}</h1>
          {description ? <p className="mt-3 max-w-4xl text-[15px] leading-7 text-muted">{description}</p> : null}
        </div>
        {action ? <div className="shrink-0">{action}</div> : null}
      </header>
      {steps ? (
        <ol aria-label="Workflow sequence" className="mt-5 grid gap-2 rounded-2xl border border-black/[0.06] bg-white/90 p-3 shadow-[var(--shadow-card)] sm:grid-cols-3 sm:gap-3 sm:p-4">
          {steps.map((step, index) => (
            <li key={step.label} className="flex min-w-0 items-center gap-3 rounded-xl px-2 py-2 sm:px-3">
              <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-grove-800 text-xs font-bold text-white">{String(index + 1).padStart(2, "0")}</span>
              <span className="text-sm font-semibold leading-5 text-ink">{step.label}</span>
              {index < steps.length - 1 ? <span aria-hidden="true" className="ml-auto hidden h-px min-w-5 flex-1 bg-honey-300 sm:block" /> : null}
            </li>
          ))}
        </ol>
      ) : null}
    </section>
  );
}
