import { useState } from "react";
import { Link } from "@tanstack/react-router";
import { PageHeader } from "@/components/hc/page-header";
import { HeroStatus, KpiCard } from "@/components/hc/kpi";
import { StatusBadge } from "@/components/hc/status-badge";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/hc/query-state";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useHoneyAuth } from "@/lib/hc/auth";
import { useHcMutation, useHcQuery } from "@/lib/hc/query";
import { fmtDate } from "@/lib/hc/format";
import type { LabTest } from "@/lib/hc/types";
import { toast } from "sonner";

export function LabWorkspace() {
  const { user, mode } = useHoneyAuth();
  const labId = user?.org_id || "";
  const queue = useHcQuery(["lab", labId, "queue"], (api) => api.labQueue(labId), {
    enabled: Boolean(labId),
  });
  const [confirm, setConfirm] = useState<{ test: LabTest; result: "PASS" | "FAIL" } | null>(null);

  const submit = useHcMutation(
    (api, input: { id: string; result: "PASS" | "FAIL" }) => api.submitLabResult(input.id, input.result),
    [["lab", labId, "queue"], ["batches"]],
  );
  // `requested` → `in_progress` is a real persisted state change
  // (`POST /api/v1/labs/tests/{id}/start`), not a cosmetic badge: the queue
  // separates samples that are waiting from samples a laboratory is actively
  // working on, and the notification inbox reflects the transition.
  const startTest = useHcMutation(
    (api, input: { id: string }) => api.startLabTest(input.id),
    [["lab", labId, "queue"], ["batches"]],
  );

  if (!labId) return <EmptyState title="No laboratory organization is associated with this account." />;
  if (queue.loading) return <LoadingBlock label="Loading laboratory queue…" />;
  if (queue.error) return <ErrorState error={queue.error} onRetry={() => void queue.refetch()} />;

  const items = queue.data || [];

  // Partition each test into exactly one bucket, in a single pass.
  //
  // The previous four independent filters double-counted: a test carrying
  // `status: "requested"` alongside `result: "PASS"` matched both `pending`
  // and `passed`, inflating the KPI total beyond the number of tests and
  // listing the same row twice in the Completed column. A result, when
  // present, is the terminal truth; the status only classifies open work.
  const { pending, testing, passed, failed } = items.reduce(
    (acc, t) => {
      const result = (t.result || "").toUpperCase();
      if (result === "PASS") acc.passed.push(t);
      else if (result === "FAIL") acc.failed.push(t);
      else {
        const status = (t.status || "").toLowerCase();
        if (status === "in_progress") acc.testing.push(t);
        else acc.pending.push(t);
      }
      return acc;
    },
    { pending: [] as LabTest[], testing: [] as LabTest[], passed: [] as LabTest[], failed: [] as LabTest[] },
  );

  const openCount = pending.length + testing.length;

  const savedNote =
    mode === "demo" ? "Recorded in demo workspace. This was not sent to HoneyChain." : "Result saved to HoneyChain.";
  const startedNote =
    mode === "demo"
      ? "Recorded in demo workspace. This was not sent to HoneyChain."
      : "Test marked as started in HoneyChain.";

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Laboratory"
        title="Test queue"
        description="Queue → test → result → certificate. A PASS is a laboratory result, not a blockchain proof of purity."
      />
      <HeroStatus
        tone={openCount ? "warn" : "ok"}
        title={
          openCount
            ? `${openCount} sample${openCount === 1 ? "" : "s"} need a result`
            : "No samples waiting"
        }
        detail="Start a pending sample to move it into testing, then record PASS or FAIL. A result is only offered once the test is in progress. Historical results stay visible."
      />
      <div className="grid gap-3 sm:grid-cols-4">
        <KpiCard level={1} label="Pending" value={pending.length} />
        <KpiCard label="In progress" value={testing.length} />
        <KpiCard label="Passed" value={passed.length} />
        <KpiCard label="Failed" value={failed.length} />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <QueueColumn
          title="Pending"
          items={pending}
          empty="No samples waiting to start."
          onAct={setConfirm}
          onStart={async (test) => {
            try {
              await startTest.mutateAsync({ id: test.id });
              toast.success(startedNote);
            } catch (err) {
              toast.error(err instanceof Error ? err.message : "The test could not be started.");
            }
          }}
          startPending={startTest.isPending}
        />
        <QueueColumn title="Testing" items={testing} empty="Nothing is in progress." onAct={setConfirm} />
        <QueueColumn title="Completed" items={[...passed, ...failed]} empty="No completed tests yet." />
      </div>

      <Dialog open={Boolean(confirm)} onOpenChange={() => setConfirm(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Record {confirm?.result}?</DialogTitle>
            <DialogDescription>
              This writes a laboratory result for {confirm?.test.batch_code || confirm?.test.batch_id}. It cannot be
              undone from this screen.
            </DialogDescription>
          </DialogHeader>
          <div className="flex justify-end gap-2">
            <Button variant="secondary" type="button" onClick={() => setConfirm(null)}>
              Cancel
            </Button>
            <Button
              variant={confirm?.result === "FAIL" ? "danger" : "primary"}
              type="button"
              disabled={submit.isPending}
              onClick={async () => {
                if (!confirm) return;
                try {
                  await submit.mutateAsync({ id: confirm.test.id, result: confirm.result });
                  toast.success(savedNote);
                  setConfirm(null);
                } catch (err) {
                  toast.error(err instanceof Error ? err.message : "Could not save result.");
                }
              }}
            >
              Confirm {confirm?.result}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function QueueColumn({
  title,
  items,
  empty,
  onAct,
  onStart,
  startPending,
}: {
  title: string;
  items: LabTest[];
  empty: string;
  onAct?: (input: { test: LabTest; result: "PASS" | "FAIL" }) => void;
  onStart?: (test: LabTest) => void | Promise<void>;
  startPending?: boolean;
}) {
  return (
    <section className="rounded-2xl bg-black/[0.03] p-3">
      <h2 className="px-1 pb-2 font-display text-lg">{title}</h2>
      {items.length === 0 ? (
        <EmptyState title={empty} />
      ) : (
        <div className="space-y-3">
          {items.map((t) => (
            <Card key={t.id} className="p-4">
              <div className="flex items-start justify-between gap-2">
                <Link to="/batches/$batchId" params={{ batchId: t.batch_id }} className="font-display text-lg">
                  {t.batch_code || t.batch_id}
                </Link>
                <StatusBadge label={t.result || t.status} />
              </div>
              <p className="mt-1 text-sm text-muted">{t.requested_note || "No test note"}</p>
              <p className="mt-1 text-xs text-muted">Requested {fmtDate(t.requested_at)}</p>
              {/* The queue → test → result order is real: a `requested` sample
                  must be started before a result can be recorded, and a result
                  is only offered once the test is actually in progress. */}
              {t.status === "requested" && onStart ? (
                <Button
                  className="mt-3 w-full"
                  type="button"
                  disabled={Boolean(startPending)}
                  onClick={() => void onStart(t)}
                >
                  {startPending ? "Starting…" : "Start testing"}
                </Button>
              ) : onAct && t.status === "in_progress" ? (
                <div className="mt-3 flex gap-2">
                  <Button className="flex-1" type="button" onClick={() => onAct({ test: t, result: "PASS" })}>
                    PASS
                  </Button>
                  <Button className="flex-1" variant="danger" type="button" onClick={() => onAct({ test: t, result: "FAIL" })}>
                    FAIL
                  </Button>
                </div>
              ) : null}
            </Card>
          ))}
        </div>
      )}
    </section>
  );
}
