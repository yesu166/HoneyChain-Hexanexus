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
    <article
      className={cn(
        "rounded-2xl bg-paper p-4 shadow-[var(--shadow-card)]",
        level === 1 && "border border-honey-200 bg-honey-50",
      )}
    >
      <p className="text-[10px] font-bold tracking-[0.13em] text-grove-700 uppercase">{label}</p>
      <p className="mt-2 font-display text-2xl leading-none text-ink tabular-nums">{value}</p>
      {hint ? <p className="mt-2 text-xs text-muted">{hint}</p> : null}
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
  const tones = {
    neutral: "bg-paper",
    ok: "bg-grove-50",
    warn: "bg-honey-50",
    bad: "bg-red-50",
  };
  return (
    <section className={cn("rounded-2xl p-5 shadow-[var(--shadow-card)]", tones[tone])}>
      <p className="text-[11px] font-bold tracking-[0.16em] text-grove-700 uppercase">Current status</p>
      <h2 className="mt-2 font-display text-2xl text-ink md:text-3xl">{title}</h2>
      <p className="mt-2 max-w-3xl text-sm leading-6 text-muted">{detail}</p>
    </section>
  );
}
