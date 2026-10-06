import { PageHeader } from "@/components/hc/page-header";
import { HeroStatus, KpiCard } from "@/components/hc/kpi";
import { BatchCard } from "@/components/hc/batch-card";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/hc/query-state";
import { QrPackagePanel } from "@/features/qr/qr-package-panel";
import { useHcQuery } from "@/lib/hc/query";
import { fmtNum, isLabVerified, packagingHint } from "@/lib/hc/format";

export function ProcessorWorkspace() {
  const batches = useHcQuery(["batches"], (api) => api.batches());

  if (batches.loading) return <LoadingBlock label="Loading processing queue…" />;
  if (batches.error) return <ErrorState error={batches.error} onRetry={() => void batches.refetch()} />;

  const all = batches.data || [];
  const incoming = all.filter((b) => !isLabVerified(b) && b.status !== "lab_failed");
  const verified = all.filter((b) => isLabVerified(b));
  const blocked = all.filter((b) => b.status === "lab_failed" || b.lab_result === "FAIL");
  const kg = all.reduce((sum, b) => sum + (b.quantity_kg || 0), 0);

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Processor"
        title="Incoming lots"
        description="Packaging is available only after laboratory verification. This portal will not pretend a blocked lot can be packed."
      />
      <HeroStatus
        tone={incoming.length ? "warn" : "ok"}
        title={
          incoming.length
            ? `${incoming.length} lot${incoming.length === 1 ? "" : "s"} waiting on laboratory verification`
            : "No lots are waiting on the lab"
        }
        detail="Open a batch for genealogy, custody, and quantity. Packaging stays disabled until the laboratory records a PASS."
      />
      <KpiCard label="Quantity on hand" value={fmtNum(kg, " kg")} hint="Sum of listed batches, as recorded. Differences are not rounded away." />

      <section>
        <h2 className="mb-3 font-display text-xl">Ready after lab verification</h2>
        {verified.length ? (
          <div className="grid gap-3 md:grid-cols-2">
            {verified.map((b) => (
              <BatchCard key={b.id} batch={b} />
            ))}
          </div>
        ) : (
          <EmptyState title="No verified lots are waiting for processing." />
        )}
      </section>

      <section>
        <h2 className="mb-3 font-display text-xl">Waiting on laboratory</h2>
        {incoming.length ? (
          <div className="grid gap-3 md:grid-cols-2">
            {incoming.map((b) => (
              <BatchCard key={b.id} batch={b} />
            ))}
          </div>
        ) : (
          <EmptyState title="No incoming lots are waiting on the lab." />
        )}
      </section>

      <section>
        <h2 className="mb-3 font-display text-xl">Held — do not package</h2>
        {blocked.length ? (
          <div className="grid gap-3 md:grid-cols-2">
            {blocked.map((b) => (
              <div key={b.id}>
                <BatchCard batch={b} />
                <p className="mt-2 px-1 text-xs text-red-800">{packagingHint(b).reason}</p>
              </div>
            ))}
          </div>
        ) : (
          <EmptyState title="No failed lots are on hold." />
        )}
      </section>

      {/* QR package identity + reuse detection — a capability of this surface,
          not a separate "QR Clone Detector" portal. */}
      <QrPackagePanel />
    </div>
  );
}
