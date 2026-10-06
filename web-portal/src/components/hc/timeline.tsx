import { fmtDate } from "@/lib/hc/format";
import { EmptyState } from "./query-state";

export function Timeline({
  items,
}: {
  items: { title: string; at?: string; detail?: string; actor?: string }[];
}) {
  if (!items.length) return <EmptyState title="No timeline events yet." />;
  return (
    <ol className="space-y-4 border-l-2 border-honey-400 pl-4">
      {items.map((item, i) => (
        <li key={`${item.title}-${i}`} className="relative">
          <span className="absolute top-1.5 -left-[1.4rem] h-2.5 w-2.5 rounded-full bg-grove-700" />
          <p className="font-semibold text-ink">{item.title}</p>
          <p className="text-xs text-muted">
            {fmtDate(item.at)}
            {item.actor ? ` · ${item.actor}` : ""}
          </p>
          {item.detail ? <p className="mt-1 text-sm text-ink/80">{item.detail}</p> : null}
        </li>
      ))}
    </ol>
  );
}

const JOURNEY = ["Hive", "Harvest", "Collection", "Lab", "Processing", "Packaging", "Product"] as const;

export function ProvenancePath({ current }: { current?: string }) {
  const idx = current
    ? JOURNEY.findIndex((step) => current.toLowerCase().includes(step.toLowerCase()))
    : -1;
  return (
    <ol className="flex flex-wrap gap-2">
      {JOURNEY.map((step, i) => {
        const done = idx >= 0 && i <= idx;
        return (
          <li
            key={step}
            className={`rounded-full px-3 py-1.5 text-xs font-semibold ${
              done ? "bg-grove-700 text-cream" : "bg-black/5 text-muted"
            }`}
          >
            {step}
          </li>
        );
      })}
    </ol>
  );
}
