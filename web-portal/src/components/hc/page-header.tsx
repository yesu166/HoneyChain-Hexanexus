import type { ReactNode } from "react";
import { Badge } from "@/components/ui/badge";
import { useHoneyAuth } from "@/lib/hc/auth";

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
  const { mode } = useHoneyAuth();
  return (
    <header className="mb-6 flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
      <div className="min-w-0">
        <div className="mb-2 flex flex-wrap items-center gap-2">
          {eyebrow ? (
            <p className="text-[11px] font-bold tracking-[0.16em] text-grove-700 uppercase">
              {eyebrow}
            </p>
          ) : null}
          <Badge tone={mode === "demo" ? "demo" : "live"}>
            {mode === "demo" ? "Demo data" : "Live API"}
          </Badge>
        </div>
        <h1 className="font-display text-3xl leading-tight text-ink md:text-[2.05rem]">{title}</h1>
        {description ? <p className="mt-2 max-w-3xl text-sm leading-6 text-muted">{description}</p> : null}
      </div>
      {action ? <div className="shrink-0">{action}</div> : null}
    </header>
  );
}
