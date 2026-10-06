import { Link } from "@tanstack/react-router";
import type { Batch } from "@/lib/hc/types";
import { fmtNum, packagingHint, trustLabel } from "@/lib/hc/format";
import { StatusBadge } from "./status-badge";

export function BatchCard({ batch }: { batch: Batch }) {
  const pack = packagingHint(batch);
  return (
    <Link
      to="/batches/$batchId"
      params={{ batchId: batch.id }}
      className="block w-full rounded-2xl bg-paper p-4 text-left shadow-[var(--shadow-card)] transition hover:shadow-[var(--shadow-card-hover)]"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="font-display text-lg text-ink">{batch.batch_code}</p>
          <p className="mt-1 text-sm text-muted">
            {batch.origin || "Origin not available"} · {fmtNum(batch.quantity_kg, " kg")}
          </p>
        </div>
        <StatusBadge label={trustLabel(batch.trust_tier)} />
      </div>
      <p className="mt-3 text-xs text-muted">{pack.reason}</p>
    </Link>
  );
}
