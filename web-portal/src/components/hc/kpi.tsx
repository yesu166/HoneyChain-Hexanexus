import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

export function KpiCard({
  label,
  value,
  hint,
  level = 2,
}: {
  label: string;
  value: ReactNode;
  hint?: string;
  level?: 1 | 2 | 3;
}) {
  return (
    <article className={cn(
      "hc-kpi-card relative min-w-0 overflow-hidden rounded-2xl border border-black/[0.06] bg-white p-4 shadow-[var(--shadow-card)] transition duration-200 hover:-translate-y-0.5 hover:shadow-[var(--shadow-card-hover)] md:p-5",
      level === 1 && "border-honey-300 bg-honey-50",
      level === 3 && "bg-white/80",
    )}>
      <span aria-hidden="true" className={cn("absolute inset-y-3 left-0 w-1 rounded-r-full", level === 1 ? "bg-honey-500" : level === 3 ? "bg-grove-100" : "bg-grove-600")} />
      <p className="pl-2 text-[10px] font-bold tracking-[0.14em] text-grove-700 uppercase">{label}</p>
      <p className="mt-2 pl-2 font-display text-2xl leading-none text-ink tabular-nums md:text-3xl">{value}</p>
      {hint ? <p className="mt-2 pl-2 text-xs leading-5 text-muted">{hint}</p> : null}
    </article>
  );
}

export function HeroStatus({
  title,
  detail,
  tone = "neutral",
}: {
  title: string;
  detail: string;
  tone?: "neutral" | "ok" | "warn" | "bad";
}) {
  const colors = {
    neutral: "border-grove-100 bg-white",
    ok: "border-grove-100 bg-grove-50",
    warn: "border-honey-200 bg-honey-50",
    bad: "border-red-200 bg-red-50",
  };
  const accents = {
    neutral: "bg-grove-600",
    ok: "bg-grove-600",
    warn: "bg-honey-500",
    bad: "bg-red-500",
  };
  return (
    <section className={cn("hc-hero-status relative overflow-hidden rounded-2xl border p-5 shadow-[var(--shadow-card)] md:p-6", colors[tone])}>
      <span aria-hidden="true" className={cn("absolute inset-y-0 left-0 w-1.5", accents[tone])} />
      <p className="pl-2 text-[10px] font-bold tracking-[0.17em] text-grove-700 uppercase">Current status</p>
      <h2 className="mt-2 pl-2 font-display text-2xl leading-tight text-ink md:text-3xl">{title}</h2>
      <p className="mt-2 max-w-3xl pl-2 text-sm leading-6 text-muted">{detail}</p>
    </section>
  );
}
