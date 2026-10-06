import { useState } from "react";
import { toast } from "sonner";
import { PageHeader } from "@/components/hc/page-header";
import { HeroStatus, KpiCard } from "@/components/hc/kpi";
import { StatusBadge } from "@/components/hc/status-badge";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/hc/query-state";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useHcMutation, useHcQuery } from "@/lib/hc/query";
import { describeApiError } from "@/lib/hc/client";
import { passportVerifyUrl } from "@/lib/hc/passport";

/**
 * QR package identity + suspicious reuse detection — a CAPABILITY of the
 * processor / packager surface, not a portal of its own.
 *
 * A printed label is the identity a consumer actually holds, so it gets a
 * first-class record here. Every verdict on this screen comes from the
 * backend's own signals: this component never decides that a code "looks
 * duplicated", it shows what `POST /qr/scan` reported and which signals caused it.
 *
 * The scan box accepts anything on purpose. A code this platform never issued
 * returns SUSPICIOUS / UNKNOWN_CODE — a real answer about a real label, not an
 * error to be hidden.
 */
export function QrPackagePanel() {
  const packages = useHcQuery(["qr", "packages"], (api) => api.qrPackages());
  const batches = useHcQuery(["batches"], (api) => api.batches());
  const flagged = useHcQuery(["qr", "scans"], (api) => api.suspiciousScans());
  const [code, setCode] = useState("");
  const [batchId, setBatchId] = useState("");
  const [quantity, setQuantity] = useState("");

  const scan = useHcMutation((api, c: string) => api.scanPackage(c), [
    ["qr", "packages"],
    ["qr", "scans"],
    ["notifications"],
  ]);
  const issue = useHcMutation(
    (api, body: { batch_id: string; quantity_kg: number }) => api.issuePackage(body),
    [["qr", "packages"]],
  );
  const recall = useHcMutation((api, c: string) => api.recallPackage(c), [
    ["qr", "packages"],
  ]);

  const rows = packages.data || [];
  const flaggedRows = flagged.data || [];

  if (packages.loading) return <LoadingBlock label="Loading package labels…" />;
  if (packages.error) {
    return <ErrorState error={packages.error} onRetry={() => void packages.refetch()} />;
  }

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="Honey Yatra QR · Processor"
        title="Honey Yatra QR — Package Labels"
        description="Issue Honey Yatra QR package identities for packed batches, and scan codes to check a label. Reuse signals are computed by HoneyChain from the recorded scan history."
      />
      <HeroStatus
        tone={flaggedRows.length ? "warn" : "ok"}
        title={
          flaggedRows.length
            ? `${flaggedRows.length} flagged scan${flaggedRows.length === 1 ? "" : "s"} on record`
            : "No suspicious scans on record"
        }
        detail="A code issued once and scanned by one organization is clean. A second organization presenting the same code is flagged as reuse."
      />
      <div className="grid gap-3 sm:grid-cols-2">
        <KpiCard label="Labels issued" value={String(rows.length)} hint="Printed identities on record." />
        <KpiCard label="Flagged scans" value={String(flaggedRows.length)} hint="Scans HoneyChain marked suspicious." />
      </div>

      <form
        className="flex flex-wrap items-end gap-3 rounded-2xl border border-cream bg-paper p-4"
        onSubmit={(e) => {
          e.preventDefault();
          if (!code.trim()) {
            toast.error("Enter a package code to scan.");
            return;
          }
          scan.mutate(code.trim(), {
            onSuccess: () => setCode(""),
            onError: (err) => toast.error(describeApiError(err).detail),
          });
        }}
      >
        <label className="text-sm">
          Scan a package code
          <Input
            className="mt-1 w-56"
            value={code}
            onChange={(e) => setCode(e.target.value)}
            placeholder="HC-XXXXXXXXXX"
          />
        </label>
        <Button type="submit" disabled={scan.isPending}>
          {scan.isPending ? "Scanning…" : "Scan Honey Yatra QR"}
        </Button>
      </form>

      {scan.data ? (
        <div
          className={`rounded-2xl border p-4 ${
            scan.data.result === "CLEAR"
              ? "border-grove-200 bg-grove-50"
              : "border-red-200 bg-red-50"
          }`}
        >
          <div className="flex items-center justify-between gap-2">
            <p className="font-display text-lg">
              {scan.data.result === "CLEAR" ? "Label verified" : "Suspicious label"}
            </p>
            <StatusBadge label={scan.data.result} />
          </div>
          {scan.data.package ? (
            <p className="mt-1 text-sm text-muted">
              {scan.data.package.package_code} · batch {scan.data.package.batch_id} ·{" "}
              {scan.data.package.quantity_kg} kg · {scan.data.package.scan_count} scan
              {scan.data.package.scan_count === 1 ? "" : "s"} on record
            </p>
          ) : (
            <p className="mt-1 text-sm text-muted">
              No package with this code has been issued by HoneyChain.
            </p>
          )}
          {scan.data.signals.length ? (
            <ul className="mt-2 space-y-1 text-sm">
              {scan.data.signals.map((s) => (
                <li key={s.code}>
                  <strong>{s.code}</strong> — {s.detail}
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      ) : null}
      <form
        className="flex flex-wrap items-end gap-3 rounded-2xl border border-cream bg-paper p-4"
        onSubmit={(e) => {
          e.preventDefault();
          const kg = Number(quantity);
          if (!batchId || !(kg > 0)) {
            toast.error("Choose a batch and enter a quantity above zero.");
            return;
          }
          issue.mutate(
            { batch_id: batchId, quantity_kg: kg },
            {
              onSuccess: () => {
                toast.success("Package label issued.");
                setQuantity("");
              },
              onError: (err) => toast.error(describeApiError(err).detail),
            },
          );
        }}
      >
        <label className="text-sm">
          Batch
          <select
            className="mt-1 rounded-xl border border-cream bg-paper px-3 py-2 text-sm"
            value={batchId}
            onChange={(e) => setBatchId(e.target.value)}
          >
            <option value="">Select a batch…</option>
            {(batches.data || []).map((b) => (
              <option key={b.id} value={b.id}>
                {b.batch_code}
              </option>
            ))}
          </select>
        </label>
        <label className="text-sm">
          Quantity (kg)
          <Input
            className="mt-1 w-32"
            value={quantity}
            onChange={(e) => setQuantity(e.target.value)}
            inputMode="decimal"
          />
        </label>
        <Button type="submit" disabled={issue.isPending}>
          {issue.isPending ? "Issuing…" : "Issue Honey Yatra QR"}
        </Button>
      </form>

      <section>
        <h3 className="mb-2 font-display text-xl">Issued labels</h3>
        {rows.length ? (
          <div className="space-y-2">
            {rows.map((p) => (
              <div
                key={p.id}
                className="flex flex-wrap items-start justify-between gap-2 rounded-2xl border border-cream bg-paper p-3"
              >
                <div>
                  <p className="font-medium">{p.package_code}</p>
                  <p className="text-xs text-muted">
                    batch {p.batch_id} · {p.quantity_kg} kg · {p.scan_count} scan
                    {p.scan_count === 1 ? "" : "s"}
                    {p.first_scan_org
                      ? ` · first scanned by ${p.first_scan_org}`
                      : ""}
                  </p>
                  {/* The label's QR encodes this LIVE public URL, never a copy
                      of the passport data — so a consumer scanning the jar
                      always resolves current provenance from the backend. */}
                  <a
                    className="mt-1 inline-block break-all text-xs text-grove-700 underline"
                    href={passportVerifyUrl(p.package_code)}
                    target="_blank"
                    rel="noreferrer"
                  >
                    QR resolves to {passportVerifyUrl(p.package_code)}
                  </a>
                </div>
                <div className="flex items-center gap-2">
                  <StatusBadge label={p.status} />
                  {p.status !== "RECALLED" ? (
                    <Button
                      size="sm"
                      variant="secondary"
                      disabled={recall.isPending}
                      onClick={() =>
                        recall.mutate(p.package_code, {
                          onSuccess: () => toast.success("Label recalled."),
                          onError: (err) => toast.error(describeApiError(err).detail),
                        })
                      }
                    >
                      Recall
                    </Button>
                  ) : null}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <EmptyState title="No package labels issued yet." />
        )}
      </section>

      <section>
        <h3 className="mb-2 font-display text-xl">Flagged scans</h3>
        {flaggedRows.length ? (
          <div className="space-y-2">
            {flaggedRows.map((s) => (
              <div
                key={s.id}
                className="rounded-2xl border border-red-200 bg-red-50 p-3 text-sm"
              >
                <p className="font-medium">
                  {s.package_code} — {s.signals?.map((x) => x.code).join(", ")}
                </p>
                {s.signals?.map((sig, i) => (
                  <p key={i} className="text-xs text-muted">
                    {sig.detail}
                  </p>
                ))}
              </div>
            ))}
          </div>
        ) : (
          <EmptyState
            title="No suspicious scans."
            detail="Every code scanned so far matched a single issued label."
          />
        )}
      </section>
    </div>
  );
}
