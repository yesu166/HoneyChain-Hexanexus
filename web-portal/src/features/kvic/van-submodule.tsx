import { useState } from "react";
import { toast } from "sonner";
import { HeroStatus, KpiCard } from "@/components/hc/kpi";
import { StatusBadge } from "@/components/hc/status-badge";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/hc/query-state";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useHcMutation, useHcQuery } from "@/lib/hc/query";
import { describeApiError } from "@/lib/hc/client";
import type { VanVisit } from "@/lib/hc/types";

/**
 * Mobile processing van — a SUBMODULE of the KVIC Field Officer surface.
 *
 * There is no "Mobile Processing Van" card in the workspace catalog and none may
 * be added: the van is field work the KVIC field officer does, so it belongs
 * here on the KVIC surface the officer already opens.
 *
 * A visit may only advance scheduled → arrived → sampled → complete, and the
 * backend derives that next state rather than accepting an arbitrary one. This
 * component therefore offers exactly the one button that is legal at each
 * point, instead of a status dropdown that could request an illegal jump.
 *
 * A van result is a FIELD OBSERVATION. The screen says so explicitly and never
 * presents a van PASS as laboratory certification, because only a laboratory may
 * change a batch's trust tier.
 */
export function VanSubmodule() {
  const dash = useHcQuery(["van", "dashboard"], (api) => api.vanDashboard());
  const batches = useHcQuery(["batches"], (api) => api.batches());
  const [vanCode, setVanCode] = useState("");
  const [target, setTarget] = useState("");
  const [sampling, setSampling] = useState<string | null>(null);
  const [sampleCode, setSampleCode] = useState("");
  const [batchId, setBatchId] = useState("");

  const invalidate = [["van", "dashboard"], ["notifications"]];

  const schedule = useHcMutation(
    (api, body: { van_code: string; target_name: string }) =>
      api.scheduleVanVisit(body),
    invalidate,
  );
  const advance = useHcMutation(
    (api, id: string) => api.advanceVanVisit(id),
    invalidate,
  );
  const sample = useHcMutation(
    (api, input: { visitId: string; batch_id: string; sample_code: string }) =>
      api.collectVanSample(input.visitId, {
        batch_id: input.batch_id,
        sample_code: input.sample_code,
      }),
    invalidate,
  );
  const record = useHcMutation(
    (api, input: { sampleId: string; result: "PASS" | "FAIL" }) =>
      api.recordVanResult(input.sampleId, input.result),
    invalidate,
  );

  const visits = dash.data?.visits || [];
  const counts = dash.data?.counts || {};
  const active = visits.filter((v) => v.status !== "COMPLETED");
  const completed = visits.filter((v) => v.status === "COMPLETED");

  if (dash.loading) return <LoadingBlock label="Loading van schedule…" />;
  if (dash.error) {
    return <ErrorState error={dash.error} onRetry={() => void dash.refetch()} />;
  }

  function submitSchedule(e: React.FormEvent) {
    e.preventDefault();
    if (!vanCode.trim()) {
      toast.error("Enter the van code.");
      return;
    }
    schedule.mutate(
      { van_code: vanCode.trim(), target_name: target.trim() },
      {
        onSuccess: () => {
          toast.success("Visit scheduled.");
          setVanCode("");
          setTarget("");
        },
        onError: (err) => toast.error(describeApiError(err).detail),
      },
    );
  }
  return (
    <div className="space-y-5">
      <HeroStatus
        tone={active.length ? "warn" : "ok"}
        title={
          active.length
            ? `${active.length} open van visit${active.length === 1 ? "" : "s"}`
            : "No open van visits"
        }
        detail="The van travels to the apiary, samples a real batch on site, and records a field result. A van result is an observation, not a laboratory certificate."
      />
      <div className="grid gap-3 sm:grid-cols-4">
        <KpiCard label="Scheduled" value={String(counts.SCHEDULED || 0)} />
        <KpiCard label="On site" value={String(counts.ARRIVED || 0)} />
        <KpiCard label="Sampled" value={String(counts.SAMPLE_COLLECTED || 0)} />
        <KpiCard label="Completed" value={String(counts.COMPLETED || 0)} />
      </div>

      <form
        onSubmit={submitSchedule}
        className="flex flex-wrap items-end gap-3 rounded-2xl border border-cream bg-paper p-4"
      >
        <label className="text-sm">
          Van code
          <Input
            className="mt-1 w-44"
            value={vanCode}
            onChange={(e) => setVanCode(e.target.value)}
            placeholder="KVIC-VAN-01"
          />
        </label>
        <label className="text-sm">
          Target apiary / FPO
          <Input
            className="mt-1 w-64"
            value={target}
            onChange={(e) => setTarget(e.target.value)}
            placeholder="Optional"
          />
        </label>
        <Button type="submit" disabled={schedule.isPending}>
          {schedule.isPending ? "Scheduling…" : "Schedule visit"}
        </Button>
      </form>

      <section>
        <h3 className="mb-2 font-display text-xl">Visits</h3>
        {visits.length ? (
          <div className="space-y-3">
            {visits.map((v) => (
              <VisitCard
                key={v.id}
                visit={v}
                batches={(batches.data || []).map((b) => ({
                  id: b.id,
                  code: b.batch_code,
                }))}
                sampling={sampling === v.id}
                sampleCode={sampleCode}
                batchId={batchId}
                onStartSample={() => {
                  setSampling(v.id);
                  setSampleCode("");
                  setBatchId("");
                }}
                onCancelSample={() => setSampling(null)}
                onSampleCode={setSampleCode}
                onBatchId={setBatchId}
                onSubmitSample={() => {
                  if (!batchId || !sampleCode.trim()) {
                    toast.error("Choose the batch being sampled and enter a sample code.");
                    return;
                  }
                  sample.mutate(
                    {
                      visitId: v.id,
                      batch_id: batchId,
                      sample_code: sampleCode.trim(),
                    },
                    {
                      onSuccess: () => {
                        toast.success("Sample recorded against the batch.");
                        setSampling(null);
                      },
                      onError: (err) => toast.error(describeApiError(err).detail),
                    },
                  );
                }}
                onAdvance={() =>
                  advance.mutate(v.id, {
                    onSuccess: () => toast.success("Visit updated."),
                    // e.g. "the van must be on site" — the real refusal, verbatim.
                    onError: (err) => toast.error(describeApiError(err).detail),
                  })
                }
                onResult={(sampleId, result) =>
                  record.mutate(
                    { sampleId, result },
                    {
                      onSuccess: () =>
                        toast.success(
                          `Field result recorded: ${result}. This does not certify the batch.`,
                        ),
                      onError: (err) => toast.error(describeApiError(err).detail),
                    },
                  )
                }
                busy={advance.isPending || sample.isPending || record.isPending}
              />
            ))}
          </div>
        ) : (
          <EmptyState
            title="No van visits scheduled."
            detail="Schedule a visit to start the field workflow."
          />
        )}
      </section>

      {completed.length ? (
        <p className="text-xs text-muted">
          {completed.length} visit{completed.length === 1 ? "" : "s"} completed. Van
          results do not change a batch&apos;s trust tier — request laboratory
          testing for that.
        </p>
      ) : null}
    </div>
  );
}

function VisitCard({
visit,
batches,
sampling,
sampleCode,
batchId,
onStartSample,
onCancelSample,
onSampleCode,
onBatchId,
onSubmitSample,
onAdvance,
onResult,
busy,
}: {
visit: VanVisit;
batches: { id: string; code: string }[];
sampling: boolean;
sampleCode: string;
batchId: string;
onStartSample: () => void;
onCancelSample: () => void;
onSampleCode: (v: string) => void;
onBatchId: (v: string) => void;
onSubmitSample: () => void;
onAdvance: () => void;
onResult: (sampleId: string, result: "PASS" | "FAIL") => void;
busy: boolean;
}) {
const onSite = visit.status === "ARRIVED" || visit.status === "SAMPLE_COLLECTED";
return (
  <div className="rounded-2xl border border-cream bg-paper p-4">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div>
        <p className="font-medium">
          {visit.van_code}
          {visit.target_name ? ` — ${visit.target_name}` : ""}
        </p>
        <p className="text-xs text-muted">Scheduled {visit.scheduled_for}</p>
      </div>
      <StatusBadge label={visit.status} />
    </div>

    {visit.samples.length ? (
      <ul className="mt-3 space-y-2">
        {visit.samples.map((s) => (
          <li key={s.id} className="rounded-xl bg-cream px-3 py-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span className="text-sm">
                {s.sample_code} · batch {s.batch_id}
              </span>
              <StatusBadge label={s.result} />
            </div>
            {s.result === "PENDING" ? (
              <div className="mt-2 flex gap-2">
                <Button
                  size="sm"
                  disabled={busy}
                  onClick={() => onResult(s.id, "PASS")}
                >
                  Field PASS
                </Button>
                <Button
                  size="sm"
                  variant="secondary"
                  disabled={busy}
                  onClick={() => onResult(s.id, "FAIL")}
                >
                  Field FAIL
                </Button>
              </div>
            ) : (
              <p className="mt-1 text-xs text-muted">
                Field observation only — not a laboratory certificate. The
                batch&apos;s trust tier is unchanged.
              </p>
            )}
          </li>
        ))}
      </ul>
    ) : null}

    {sampling ? (
      <div className="mt-3 flex flex-wrap items-end gap-3">
        <label className="text-sm">
          Batch sampled
          <select
            className="mt-1 rounded-xl border border-cream bg-paper px-3 py-2 text-sm"
            value={batchId}
            onChange={(e) => onBatchId(e.target.value)}
          >
            <option value="">Select batch…</option>
            {batches.map((b) => (
              <option key={b.id} value={b.id}>
                {b.code}
              </option>
            ))}
          </select>
        </label>
        <label className="text-sm">
          Sample code
          <Input
            className="mt-1 w-40"
            value={sampleCode}
            onChange={(e) => onSampleCode(e.target.value)}
          />
        </label>
        <Button onClick={onSubmitSample} disabled={busy}>
          Record sample
        </Button>
        <Button variant="secondary" onClick={onCancelSample}>
          Cancel
        </Button>
      </div>
    ) : null}

    {/* Exactly one advance action is offered, matching the only transition the
        backend permits from the current state. */}
    <div className="mt-3 flex gap-2">
      {visit.status === "SCHEDULED" ? (
        <Button size="sm" disabled={busy} onClick={onAdvance}>
          Record arrival
        </Button>
      ) : null}
      {onSite && !sampling ? (
        <Button size="sm" variant="secondary" disabled={busy} onClick={onStartSample}>
          Collect sample
        </Button>
      ) : null}
      {visit.status === "SAMPLE_COLLECTED" && visit.samples.length ? (
        <Button size="sm" disabled={busy} onClick={onAdvance}>
          Complete visit
        </Button>
      ) : null}
    </div>
    {visit.status === "ARRIVED" && !visit.samples.length ? (
      <p className="mt-2 text-xs text-muted">
        Collect a sample before this visit can be completed.
      </p>
    ) : null}
  </div>
);
}
