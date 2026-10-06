import { useRef, useState } from "react";
import { Link, useParams } from "@tanstack/react-router";
import { PageHeader } from "@/components/hc/page-header";
import { StatusBadge } from "@/components/hc/status-badge";
import { Timeline } from "@/components/hc/timeline";
import { QueryTable } from "@/components/hc/data-table";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/hc/query-state";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useHoneyAuth } from "@/lib/hc/auth";
import { useHcMutation, useHcQuery } from "@/lib/hc/query";
import {
  asString,
  fmtDate,
  fmtNum,
  isLabVerified,
  packagingHint,
  trustLabel,
} from "@/lib/hc/format";
import { ledgerExplanation, ledgerHeadline, ledgerTone, readLedgerHealth } from "@/lib/hc/blockchain";
import { PassportQrLabel } from "@/features/passport/qr-label";
import { toast } from "sonner";
import type { CustodyAction, DiscrepancyItem } from "@/lib/hc/types";

export function BatchDetailPage() {
  const { batchId } = useParams({ strict: false }) as { batchId: string };
  const { user, mode } = useHoneyAuth();
  const batches = useHcQuery(["batches"], (api) => api.batches());
  const genealogy = useHcQuery(["batches", batchId, "genealogy"], (api) => api.genealogy(batchId));
  const custody = useHcQuery(["batches", batchId, "custody"], (api) => api.custody(batchId));
  const labs = useHcQuery(["batches", batchId, "labs"], (api) => api.labTests(batchId));
  const certs = useHcQuery(["batches", batchId, "certs"], (api) => api.batchCertificates(batchId));
  const verify = useHcQuery(["batches", batchId, "verify"], (api) => api.verification(batchId));
  const disc = useHcQuery(["batches", batchId, "disc"], (api) => api.discrepancies(batchId));
  const chain = useHcQuery(["chain", "health"], (api) => api.blockchainHealth());
  // Canonical provenance for this batch: material origin (hive → harvest) and
  // mass balance, which the separate custody / genealogy queries never answer.
  const provenance = useHcQuery(["batches", batchId, "provenance"], (api) =>
    api.batchProvenance(batchId),
  );
  // Real laboratory directory behind the test-request selector.
  const labDirectory = useHcQuery(["labs"], (api) => api.labs());
  const custodyRetryKey = useRef(crypto.randomUUID());

  const addCustody = useHcMutation(
    (api, body: { action: CustodyAction; notes?: string; client_id?: string }) => api.addCustodyEvent(batchId, body),
    [["batches", batchId, "custody"]],
  );
  const issueCert = useHcMutation(
    (api) => api.issueCertificate({ batch_id: batchId, lab_id: user?.org_id, certificate_type: "quality", anchor: false }),
    [["batches", batchId, "certs"]],
  );
  // The FPO-to-laboratory link: `POST /batches/{id}/lab-test` exists on the
  // backend and `requestLabTest` exists on the client interface, but no screen
  // ever called it — so a batch could never be sent to a lab from this portal.
  // The lab is identified by its organization key (the `lab_id` HoneyChain
  // issues); nothing here guesses or hardcodes one, the operator types the key
  // the laboratory gave them.
  const requestLab = useHcMutation(
    (api, input: { labId: string; note?: string }) => api.requestLabTest(batchId, input.labId, input.note),
    [["batches", batchId, "labs"], ["batches"]],
  );
  const [labKey, setLabKey] = useState("");
  const [labNote, setLabNote] = useState("");

  const batch = (batches.data || []).find((b) => b.id === batchId);
  if (batches.loading) return <LoadingBlock />;
  if (batches.error) return <ErrorState error={batches.error} onRetry={() => void batches.refetch()} />;
  if (!batch) return <EmptyState title="This batch was not found." detail="It may be outside your organization or not yet created." />;

  const pack = packagingHint(batch);
  // The ledger badge describes the ledger HoneyChain is actually using. It used to
  // run the *connection* status through the per-anchor label, which printed
  // "Ledger: Anchor state unknown" on a perfectly healthy Fabric network.
  //
  // A *failed* health request is a third state, distinct from both "local" and
  // "fabric". `readLedgerHealth(undefined)` used to be handed to
  // `ledgerExplanation` as if the API had answered, producing the flat claim
  // "This deployment is not backed by a distributed ledger" — a statement
  // about the deployment that no one ever made, printed because a request
  // failed. It now says only that the status is unknown.
  const chainUnreadable = Boolean(chain.error);
  const ledger = readLedgerHealth(chain.data);
  const chainLabel = chainUnreadable
    ? { label: "Blockchain status unknown", tone: "warn" as const }
    : { label: ledgerHeadline(ledger), tone: ledgerTone(ledger) };
  const canPack = user?.role === "processor" || user?.role === "admin";
  const canCert = (user?.role === "lab" || user?.role === "admin") && isLabVerified(batch);
  // Requesting a lab test is the FPO's action (admins may do it too); the
  // backend RBAC is what actually enforces it — this only decides whether the
  // button is rendered.
  const canRequestTest = user?.role === "fpo" || user?.role === "admin";
  const saved = mode === "demo" ? "Recorded in demo workspace. This was not sent to HoneyChain." : "Saved to HoneyChain.";
  // The selector is used only when HoneyChain actually returned laboratories.
  // Otherwise the operator types the key the laboratory issued, and the form
  // says why — an unreadable directory must never render as "no labs exist".
  const directoryLabs = labDirectory.data || [];
  const directoryReady =
    !labDirectory.loading && !labDirectory.error && directoryLabs.length > 0;
  const directoryNote = labDirectory.loading
    ? "Loading the HoneyChain laboratory directory…"
    : labDirectory.error
      ? "HoneyChain did not return its laboratory directory, so the organization key must be typed exactly as the laboratory issued it."
      : directoryLabs.length === 0
        ? "HoneyChain has no laboratory organizations on record yet, so the organization key must be typed exactly as the laboratory issued it."
        : "";

  // The verification caveat is HoneyChain's own sentence about this lot. When
  // the request failed it must not be replaced by `pack.reason`, which for a
  // lab-verified lot is the positive claim "Laboratory verification is on
  // record" — printed precisely when the API said nothing at all.
  //
  // `verification()` is typed `Record<string, unknown>` because the shape is not
  // guaranteed, so the caveat is only shown when it is genuinely a string.
  const verifyUnreadable = Boolean(verify.error);
  const rawCaveat = verify.data?.caveat;
  const caveat = typeof rawCaveat === "string" && rawCaveat.trim() ? rawCaveat.trim() : "";
  const caveatText = verifyUnreadable
    ? "HoneyChain did not return a verification statement for this batch, so none is shown here."
    : caveat
      ? caveat
      : "HoneyChain returned no verification caveat for this batch.";

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="Batch"
        title={batch.batch_code}
        description={`${batch.origin || "Origin not available"} · ${fmtNum(batch.quantity_kg, " kg")} · ${batch.honey_type}`}
        action={<StatusBadge label={trustLabel(batch.trust_tier)} />}
      />
      <Card>
        <div className="flex flex-wrap items-center gap-2">
          <StatusBadge label={batch.status} />
          <Badge tone={chainLabel.tone}>{chainLabel.label}</Badge>
        </div>
        {mode !== "demo" ? (
          <p className="mt-2 text-xs text-muted">
            {chainUnreadable
              ? "HoneyChain did not return its blockchain status, so this deployment's ledger is unknown rather than confirmed absent."
              : ledgerExplanation(ledger)}
          </p>
        ) : null}
        <p className="mt-3 text-sm text-muted">{caveatText}</p>
        <div className="mt-4 flex flex-wrap gap-2">
          {canPack ? (
            pack.allowed ? (
              <Button
                type="button"
                disabled={addCustody.isPending}
                onClick={async () => {
                  try {
                    await addCustody.mutateAsync({
                      action: "PACKAGING",
                      notes: "Packaging started after laboratory verification.",
                      client_id: custodyRetryKey.current,
                    });
                    custodyRetryKey.current = crypto.randomUUID();
                    toast.success(saved);
                  } catch (err) {
                    toast.error(err instanceof Error ? err.message : "Packaging was not recorded.");
                  }
                }}
              >
                Start packaging
              </Button>
            ) : (
              <Button type="button" disabled title={pack.reason}>
                Start packaging
              </Button>
            )
          ) : null}
          {canCert ? (
            <Button
              variant="secondary"
              type="button"
              disabled={issueCert.isPending}
              onClick={async () => {
                try {
                  await issueCert.mutateAsync(undefined as void);
                  toast.success(saved);
                } catch (err) {
                  toast.error(err instanceof Error ? err.message : "Certificate was not issued.");
                }
              }}
            >
              Issue certificate
            </Button>
          ) : null}
          <Button variant="link" asChild>
            <Link to="/passport" search={{ code: batch.batch_code }}>
              Open consumer passport
            </Link>
          </Button>
        </div>
        {!pack.allowed && canPack ? (
          <p className="mt-2 text-sm text-honey-600">{pack.reason}</p>
        ) : null}

        {/* FPO/admin send this batch to a laboratory. The selector is driven by
            `GET /api/v1/labs`, so a request can only name a laboratory
            HoneyChain actually has on record — nothing here is hardcoded. When
            the directory cannot be read the form falls back to the organization
            key the laboratory issued, and says so, because an unreadable
            directory must never render as "there are no laboratories". The
            backend enforces the rest (batch ownership, lab scope, duplicates). */}
        {canRequestTest ? (
          <form
            className="mt-4 space-y-3 border-t border-black/5 pt-4"
            onSubmit={(e) => {
              e.preventDefault();
              const key = labKey.trim();
              if (!key) {
                toast.error(
                  directoryReady
                    ? "Choose a laboratory from the list."
                    : "Enter the laboratory organization key HoneyChain gave you.",
                );
                return;
              }
              void (async () => {
                try {
                  await requestLab.mutateAsync({ labId: key, note: labNote.trim() || undefined });
                  setLabKey("");
                  setLabNote("");
                  toast.success(`Laboratory test requested. ${saved}`);
                } catch (err) {
                  toast.error(err instanceof Error ? err.message : "The laboratory test was not requested.");
                }
              })();
            }}
          >
            <p className="text-sm font-semibold">Request a laboratory test</p>
            <label className="block space-y-1 text-xs text-muted">
              Laboratory
              {directoryReady ? (
                <select
                  value={labKey}
                  onChange={(e) => setLabKey(e.target.value)}
                  className="h-11 w-full rounded-xl border border-black/10 bg-paper px-3 text-sm text-ink"
                >
                  <option value="">Select a laboratory…</option>
                  {directoryLabs.map((lab) => (
                    <option key={lab.id} value={lab.organization_key || lab.id}>
                      {lab.name}
                      {lab.district ? ` · ${lab.district}` : ""}
                    </option>
                  ))}
                </select>
              ) : (
                <input
                  value={labKey}
                  onChange={(e) => setLabKey(e.target.value)}
                  placeholder="e.g. the lab's org key from HoneyChain"
                  className="h-11 w-full rounded-xl border border-black/10 bg-paper px-3 text-sm text-ink"
                />
              )}
            </label>
            {!directoryReady && directoryNote ? (
              <p className="text-xs text-muted">{directoryNote}</p>
            ) : null}
            <label className="block space-y-1 text-xs text-muted">
              Note for the laboratory (optional)
              <input
                value={labNote}
                onChange={(e) => setLabNote(e.target.value)}
                placeholder="What should be tested?"
                className="h-11 w-full rounded-xl border border-black/10 bg-paper px-3 text-sm text-ink"
              />
            </label>
            <Button
              type="submit"
              variant="secondary"
              disabled={requestLab.isPending || !labKey.trim()}
            >
              {requestLab.isPending ? "Requesting…" : "Request lab test"}
            </Button>
          </form>
        ) : null}
      </Card>

      {/* The label is built from `batch.batch_code` — the identifier the API
          returned for this lot — so the printed QR and the public passport
          resolve to the same record. No identifier is generated client-side. */}
      <PassportQrLabel
        batchCode={batch.batch_code}
        honeyType={batch.honey_type}
        origin={batch.origin}
      />



      {/* A failed discrepancy request used to render nothing at all, which reads
          as "no quantity discrepancies exist on this lot". A tamper signal
          that silently disappears is worse than a visible error. */}
      {disc.error ? (
        <ErrorState error={disc.error} onRetry={() => void disc.refetch()} />
      ) : (disc.data?.discrepancies || []).length ? (
        <div className="space-y-3">
          {(disc.data?.discrepancies || []).map((item, i) => {
            const d = item as unknown as DiscrepancyItem;
            return (
              <Card key={i} className="border border-honey-200 bg-honey-50">
                <p className="font-semibold">{d.title}</p>
                <p className="mt-2 text-sm">
                  Reference {fmtNum(d.reference_quantity_kg, " kg")} vs claimed {fmtNum(d.claimed_quantity_kg, " kg")} ·
                  delta {fmtNum(d.delta_kg, " kg")}
                </p>
                <StatusBadge label={d.status} />
              </Card>
            );
          })}
        </div>
      ) : null}

      <section>
        <h2 className="mb-2 font-display text-xl">Provenance</h2>
        {/* One aggregated answer to "where did this honey come from and does it
            add up". Material origin and mass balance are only available here —
            the custody and genealogy queries answer different questions. A
            failed request must not read as "this batch has no origin". */}
        {provenance.loading ? (
          <LoadingBlock label="Loading provenance…" />
        ) : provenance.error ? (
          <ErrorState error={provenance.error} onRetry={() => void provenance.refetch()} />
        ) : provenance.data ? (
          <div className="space-y-4">
            <div className="flex flex-wrap items-center gap-2">
              <StatusBadge
                label={
                  provenance.data.mass_balance.balanced
                    ? "Mass balance reconciles"
                    : "Mass balance mismatch"
                }
              />
              <span className="text-sm text-muted">
                {fmtNum(provenance.data.mass_balance.allocated_kg, " kg")} allocated of{" "}
                {fmtNum(provenance.data.mass_balance.batch_quantity_kg, " kg")}
                {Number(provenance.data.mass_balance.unallocated_kg) > 0
                  ? ` · ${fmtNum(provenance.data.mass_balance.unallocated_kg, " kg")} unallocated`
                  : ""}
              </span>
            </div>
            {provenance.data.hive_sources.length || provenance.data.harvest_sources.length ? (
              <div className="overflow-x-auto rounded-2xl bg-paper shadow-[var(--shadow-card)]">
                <table className="min-w-full text-left text-sm">
                  <thead className="bg-grove-50 text-[10px] tracking-[0.12em] text-grove-800 uppercase">
                    <tr>
                      <th className="px-4 py-3 font-bold">Hive</th>
                      <th className="px-4 py-3 font-bold">Harvested</th>
                      <th className="px-4 py-3 font-bold">Harvest</th>
                      <th className="px-4 py-3 font-bold">Allocated</th>
                      <th className="px-4 py-3 font-bold">Type</th>
                    </tr>
                  </thead>
                  <tbody>
                    {provenance.data.harvest_sources.map((h, i) => {
                      const hive = provenance.data.hive_sources.find(
                        (x) => x.hive_id === h.hive_id,
                      );
                      return (
                        <tr key={String(h.harvest_id ?? i)} className="border-t border-black/5">
                          <td className="px-4 py-3 align-top">
                            {asString(hive?.hive_code) || asString(h.hive_id)}
                          </td>
                          <td className="px-4 py-3 align-top">{fmtDate(h.harvested_at)}</td>
                          <td className="px-4 py-3 align-top">
                            {fmtNum(Number(h.quantity_kg), " kg")}
                          </td>
                          <td className="px-4 py-3 align-top">
                            {fmtNum(Number(h.allocated_kg), " kg")}
                          </td>
                          <td className="px-4 py-3 align-top">{asString(h.honey_type)}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            ) : (
              <EmptyState
                title="HoneyChain has no harvest records linked to this batch."
                detail="Material origin appears here once the harvests behind this lot are linked to it."
              />
            )}
          </div>
        ) : null}
      </section>
      <section>
        <h2 className="mb-2 font-display text-xl">Custody</h2>
        {/* Custody is the tamper-evidence trail. Rendering a failed request as
            "No timeline events yet." asserts that a batch has no custody record
            at all, which is the opposite of the truth when the answer was a
            403. */}
        {custody.loading ? (
          <LoadingBlock label="Loading custody events…" />
        ) : custody.error ? (
          <ErrorState error={custody.error} onRetry={() => void custody.refetch()} />
        ) : (
          <Timeline
            items={(custody.data || []).map((c) => ({
              title: c.action.replaceAll("_", " "),
              at: c.event_at,
              actor: c.actor,
              detail: c.notes,
            }))}
          />
        )}
      </section>
      <section>
        <h2 className="mb-2 font-display text-xl">Genealogy</h2>
        <QueryTable
          query={genealogy}
          loadingLabel="Loading genealogy…"
          empty="No genealogy nodes were returned."
          columns={[
            { key: "code", label: "Batch" },
            { key: "rel", label: "Relation" },
            { key: "qty", label: "Quantity" },
          ]}
          rows={(data) =>
            (data || []).map((n) => ({
              code: asString(n.batch_code || n.id),
              rel: asString(n.relationship),
              qty: fmtNum(Number(n.quantity_kg), " kg"),
            }))
          }
        />
      </section>
      <section>
        <h2 className="mb-2 font-display text-xl">Laboratory history</h2>
        {/* "No laboratory tests are on this batch yet." must never stand in for
            a 403 on the lab-tests route. */}
        <QueryTable
          query={labs}
          loadingLabel="Loading laboratory tests…"
          empty="No laboratory tests are on this batch yet."
          columns={[
            { key: "status", label: "Status" },
            { key: "result", label: "Result" },
            { key: "when", label: "Tested" },
          ]}
          rows={(data) =>
            (data || []).map((t) => ({
              status: <StatusBadge label={t.status} />,
              result: t.result || "Not available",
              when: fmtDate(t.tested_at),
            }))
          }
        />
      </section>
      <section>
        <h2 className="mb-2 font-display text-xl">Certificates</h2>
        <QueryTable
          query={certs}
          loadingLabel="Loading certificates…"
          empty="No certificates have been issued for this batch."
          columns={[
            { key: "id", label: "Certificate" },
            { key: "status", label: "Status" },
          ]}
          rows={(data) =>
            (data || []).map((c) => ({
              id: c.certificate_id,
              status: <StatusBadge label={c.status} />,
            }))
          }
        />
      </section>
    </div>
  );
}
