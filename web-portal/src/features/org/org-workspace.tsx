import { Link } from "@tanstack/react-router";
import { useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { PageHeader } from "@/components/hc/page-header";
import { HeroStatus, KpiCard } from "@/components/hc/kpi";
import { BatchCard } from "@/components/hc/batch-card";
import { DataTable } from "@/components/hc/data-table";
import { StatusBadge } from "@/components/hc/status-badge";
import { EmptyState, ErrorState, LoadingBlock, attentionSummary } from "@/components/hc/query-state";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useHoneyAuth } from "@/lib/hc/auth";
import { MarketLinkagePanel } from "@/features/market/market-linkage-panel";
import { useHcQuery, useHcMutation } from "@/lib/hc/query";
import { asString, fmtDate, fmtNum, isDeviceHealthy } from "@/lib/hc/format";
import type { BatchCreateBody, Harvest, LabTest } from "@/lib/hc/types";

interface ActionItem {
  id: string;
  title: string;
  next: string;
  to?: string;
  batchId?: string;
}

/**
 * FPO / organization workspace.
 *
 * Every section reads from the live HoneyChain API: the org dashboard counters,
 * the org's harvests, its batches, the laboratory tests on those batches, the
 * org's hives and IoT devices, and its notifications. Nothing here is derived
 * from demo fixtures when the session is live.
 */
export function OrgWorkspace() {
  const { user } = useHoneyAuth();
  const orgId = user?.org_id || "";

  const dash = useHcQuery(["org", orgId, "dashboard"], (api) => api.orgDashboard(orgId), {
    enabled: Boolean(orgId),
  });
  const harvests = useHcQuery(["harvests"], (api) => api.harvests(), {
    enabled: Boolean(orgId),
  });
  const batches = useHcQuery(["batches"], (api) => api.batches(), {
    enabled: Boolean(orgId),
  });
  const hives = useHcQuery(["hives"], (api) => api.hives(), {
    enabled: Boolean(orgId),
  });
  const devices = useHcQuery(["iot", "devices"], (api) => api.iotDevices(), {
    enabled: Boolean(orgId),
  });
  const notes = useHcQuery(["notifications"], (api) => api.notifications(), {
    enabled: Boolean(orgId),
  });

  const orgBatches = useMemo(
    () => (batches.data || []).filter((b) => b.organization_id === orgId),
    [batches.data, orgId],
  );
  const batchKey = orgBatches.map((b) => b.id).sort().join(",");

  // HoneyChain lists laboratory tests per batch (GET /batches/{id}/lab-tests).
  // One request per batch of this org.
  //
  // A per-batch failure is collected rather than swallowed. Swallowing it as
  // `[]` made a 403 indistinguishable from "this batch has no tests", which
  // then rendered as "No laboratory tests yet." and quietly dropped pending
  // items from the action list. The first real failure is now surfaced so the
  // screen can say the data is unavailable instead of absent.
  const labTests = useHcQuery(
    ["org", orgId, "lab-tests", batchKey || "none"],
    async (api): Promise<LabTest[]> => {
      const results = await Promise.allSettled(orgBatches.map((b) => api.labTests(b.id)));
      const failure = results.find((r) => r.status === "rejected");
      if (failure && failure.status === "rejected") throw failure.reason;
      return results.flatMap((r) => (r.status === "fulfilled" ? r.value : []));
    },
    { enabled: Boolean(batchKey) },
  );

  if (!orgId) {
    return <EmptyState title="No organization is associated with this account." />;
  }
  if (dash.loading) return <LoadingBlock label="Loading organization operations…" />;
  if (dash.error) return <ErrorState error={dash.error} onRetry={() => void dash.refetch()} />;
  if (!dash.data) return <EmptyState title="This organization has no dashboard data yet." />;

  const d = dash.data;
  // Each input to the action list is paired with its own error state. The
  // summary below claims "nothing needs attention", and that claim is only
  // honest when all three lists were actually readable.
  const testsUnreadable = Boolean(labTests.error);
  const devicesUnreadable = Boolean(devices.error);
  const notesUnreadable = Boolean(notes.error);

  const pendingTests = (labTests.data || []).filter((t) => !t.result);
  const badDevices = (devices.data || []).filter((dev) => !isDeviceHealthy(dev.device_status));
  const unreadNotes = (notes.data?.items || []).filter((n) => !n.read);

  const actionItems: ActionItem[] = [
    ...unreadNotes.map((n) => ({
      id: `note-${n.notification_id}`,
      title: n.title,
      next: n.recommended_action,
      to: "/alerts",
      batchId: n.batch_id || undefined,
    })),
    ...pendingTests.map((t) => ({
      id: `test-${t.id}`,
      title: `Laboratory verification pending for ${t.batch_code || t.batch_id}`,
      next: "Track the lab result",
      batchId: t.batch_id,
    })),
    ...badDevices.map((dev) => ({
      id: `dev-${dev.device_id}`,
      title: `${dev.device_name} is ${dev.device_status}`,
      next: "Check the sensor",
      batchId: undefined as string | undefined,
    })),
  ];

  const actionState = attentionSummary({
    count: actionItems.length,
    errored: testsUnreadable || devicesUnreadable || notesUnreadable,
    clean: "No pending organization actions",
    counted: (n) => `${n} action${n === 1 ? "" : "s"} need attention`,
  });

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="FPO / Organization"
        title={d.org_name || asString(user?.name, "Organization")}
        description="Today’s work: collection, batch pipeline, verification, and hive or device problems."
      />
      <HeroStatus
        tone={actionState.tone}
        title={actionState.title}
        detail={
          actionState.tone === "bad"
            ? "Part of this list could not be read from HoneyChain, so the items below are incomplete rather than genuinely empty. Harvests arrive from beekeeper phones; bundle them into batches, route them through the supply chain, and keep verification on record."
            : "Harvests arrive from beekeeper phones. Bundle them into batches, route them through the supply chain, and keep verification on record."
        }
      />

      {testsUnreadable || devicesUnreadable || notesUnreadable ? (
        <ErrorState
          error={labTests.error || devices.error || notes.error}
          onRetry={() => {
            void labTests.refetch();
            void devices.refetch();
            void notes.refetch();
          }}
        />
      ) : null}

      {actionItems.length ? (
        <Card>
          <h2 className="font-display text-xl">Action required</h2>
          <ul className="mt-3 space-y-3">
            {actionItems.slice(0, 6).map((item) => (
              <li
                key={item.id}
                className="flex flex-col gap-1 border-b border-black/5 pb-3 last:border-0 sm:flex-row sm:items-center sm:justify-between"
              >
                <div>
                  <p className="font-semibold">{item.title}</p>
                  <p className="text-sm text-muted">{item.next}</p>
                </div>
                {item.batchId ? (
                  <Link
                    to="/batches/$batchId"
                    params={{ batchId: item.batchId }}
                    className="text-sm font-semibold text-grove-700"
                  >
                    Open
                  </Link>
                ) : item.to ? (
                  <Link to={item.to} className="text-sm font-semibold text-grove-700">
                    Open
                  </Link>
                ) : (
                  <span className="text-sm font-semibold text-muted">Needs attention</span>
                )}
              </li>
            ))}
          </ul>
        </Card>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard label="Beekeepers" value={fmtNum(d.active_beekeepers)} />
        <KpiCard label="Hives" value={fmtNum(d.hives)} />
        <KpiCard label="Collected harvests" value={fmtNum(d.collections)} />
        <KpiCard
          label="Verified batches"
          value={`${fmtNum(d.verified_batches)} / ${fmtNum(d.batches)}`}
        />
      </div>

      <Tabs defaultValue="collection">
        <TabsList>
          <TabsTrigger value="collection">Collection</TabsTrigger>
          <TabsTrigger value="batches">Batch pipeline</TabsTrigger>
          <TabsTrigger value="quality">Verification</TabsTrigger>
          <TabsTrigger value="market">Market linkage</TabsTrigger>
          <TabsTrigger value="hives">Hives &amp; devices</TabsTrigger>
        </TabsList>

        <TabsContent value="collection">
          <div className="space-y-4">
            {harvests.error ? (
              <ErrorState error={harvests.error} onRetry={() => void harvests.refetch()} />
            ) : harvests.loading ? (
              <LoadingBlock label="Loading incoming harvests…" />
            ) : (
              <CreateBatchCard harvests={harvests.data || []} orgId={orgId} />
            )}
            {harvests.error || harvests.loading ? null : (
              <DataTable
                empty="No harvests have been recorded yet. Beekeepers record harvests from the HoneyChain app."
                columns={[
                  { key: "type", label: "Honey" },
                  { key: "qty", label: "Quantity" },
                  { key: "when", label: "Harvested" },
                  { key: "state", label: "Collection" },
                ]}
                rows={(harvests.data || []).map((h) => ({
                  type: h.honey_type || "Not specified",
                  qty: fmtNum(h.quantity_kg, " kg"),
                  when: fmtDate(h.harvested_at),
                  state: h.collected ? "Collected" : "Waiting pickup",
                }))}
              />
            )}
          </div>
        </TabsContent>

        <TabsContent value="batches">
          {batches.error ? (
            <ErrorState error={batches.error} onRetry={() => void batches.refetch()} />
          ) : batches.loading ? (
            <LoadingBlock label="Loading batches…" />
          ) : orgBatches.length ? (
            <div className="grid gap-3 md:grid-cols-2">
              {orgBatches.map((b) => (
                <BatchCard key={b.id} batch={b} />
              ))}
            </div>
          ) : (
            <EmptyState
              title="No batches are in the pipeline yet."
              detail="Bundle collected harvests into a batch in the Collection tab. This portal does not invent batch records."
            />
          )}
        </TabsContent>

        <TabsContent value="quality">
          {!batchKey ? (
            <EmptyState
              title="No laboratory tests yet."
              detail="Tests appear here after a batch is submitted for laboratory verification."
            />
          ) : labTests.error ? (
            <ErrorState error={labTests.error} onRetry={() => void labTests.refetch()} />
          ) : labTests.loading ? (
            <LoadingBlock label="Loading laboratory tests…" />
          ) : (labTests.data || []).length === 0 ? (
            <EmptyState title="No laboratory tests yet." />
          ) : (
            <DataTable
              empty="No laboratory tests are waiting."
              columns={[
                { key: "batch", label: "Batch" },
                { key: "status", label: "Status" },
                { key: "result", label: "Result" },
                { key: "note", label: "Requested" },
              ]}
              rows={(labTests.data || []).map((t) => ({
                batch: t.batch_code || t.batch_id,
                status: <StatusBadge label={t.status} />,
                result: t.result ? <StatusBadge label={t.result} /> : "Awaiting result",
                note: t.requested_note || "Not specified",
              }))}
            />
          )}
        </TabsContent>

{/* Market linkage is a capability of this workspace, not a separate
            portal — it has no card in the workspace catalog. */}
        <TabsContent value="market">
          <MarketLinkagePanel />
        </TabsContent>
        <TabsContent value="hives">
          <div className="grid gap-4 lg:grid-cols-2">
            <div>
              <h3 className="mb-2 font-display text-lg">Hives</h3>
              {hives.error ? (
                <ErrorState error={hives.error} onRetry={() => void hives.refetch()} />
              ) : hives.loading ? (
                <LoadingBlock label="Loading hives…" />
              ) : (
                <DataTable
                  empty="No hives have been registered yet."
                  columns={[
                    { key: "code", label: "Hive" },
                    { key: "status", label: "Status" },
                    { key: "loc", label: "Location" },
                  ]}
                  rows={(hives.data || []).map((h) => ({
                    code: h.hive_code,
                    status: <StatusBadge label={h.status} />,
                    loc: h.location || "Not available",
                  }))}
                />
              )}
            </div>
            <div>
              <h3 className="mb-2 font-display text-lg">Devices</h3>
              {devices.error ? (
                <ErrorState error={devices.error} onRetry={() => void devices.refetch()} />
              ) : devices.loading ? (
                <LoadingBlock label="Loading devices…" />
              ) : (
                <DataTable
                  empty="No IoT devices are assigned yet."
                  columns={[
                    { key: "name", label: "Device" },
                    { key: "status", label: "Status" },
                    { key: "seen", label: "Last seen" },
                  ]}
                  rows={(devices.data || []).map((dev) => ({
                    name: dev.device_name,
                    status: <StatusBadge label={dev.device_status} />,
                    seen: fmtDate(dev.last_seen),
                  }))}
                />
              )}
            </div>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}

/**
 * Batch creation from real uncollected harvests (POST /api/v1/batches with
 * harvest_ids). The batch inherits quantity and honey type from the selected
 * harvests — the portal never invents quantities.
 */
function CreateBatchCard({ harvests, orgId }: { harvests: Harvest[]; orgId: string }) {
  const uncollected = harvests.filter((h) => !h.collected);
  const [selected, setSelected] = useState<string[]>([]);
  const [code, setCode] = useState("");
  const [origin, setOrigin] = useState("");
  const retryKey = useRef(crypto.randomUUID());

  const chosen = uncollected.filter((h) => selected.includes(h.id));
  const totalKg = chosen.reduce((sum, h) => sum + Number(h.quantity_kg || 0), 0);
  const honeyType = chosen[0]?.honey_type || "";

  const createBatch = useHcMutation(
    (api, body: BatchCreateBody) => api.createBatch(body),
    [["org", orgId, "dashboard"], ["batches"], ["harvests"], ["org", orgId, "lab-tests"]],
  );

  if (uncollected.length === 0) {
    return (
      <Card>
        <h2 className="font-display text-xl">Create a batch</h2>
        <EmptyState
          title="No uncollected harvests are waiting."
          detail="Harvests appear here after beekeepers record them in the HoneyChain app."
        />
      </Card>
    );
  }

  const submit = async () => {
    if (!chosen.length) {
      toast.error("Select at least one harvest to bundle into a batch.");
      return;
    }
    if (totalKg <= 0) {
      toast.error("The selected harvests carry no quantity.");
      return;
    }
    try {
      const batch = await createBatch.mutateAsync({
        batch_code: code.trim() || `B-${Date.now().toString(36).toUpperCase()}`,
        quantity_kg: totalKg,
        honey_type: honeyType || undefined,
        origin: origin.trim() || undefined,
        harvest_ids: chosen.map((h) => h.id),
        harvest_allocations: chosen.map((h) => ({
          harvest_id: h.id,
          quantity_kg: Number(h.quantity_kg),
        })),
        client_id: retryKey.current,
      });
      retryKey.current = crypto.randomUUID();
      toast.success(`Batch ${batch.batch_code} created in HoneyChain.`);
      setSelected([]);
      setCode("");
      setOrigin("");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "The batch could not be created.");
    }
  };

  return (
    <Card>
      <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
        <h2 className="font-display text-xl">Create a batch from incoming harvests</h2>
        <span className="text-sm text-muted">
          {selected.length} of {uncollected.length} selected · {fmtNum(totalKg, " kg")}
        </span>
      </div>
      <ul className="mt-3 space-y-2">
        {uncollected.map((h) => {
          const checked = selected.includes(h.id);
          return (
            <li key={h.id}>
              <label className="flex cursor-pointer items-center gap-3 rounded-xl border border-black/10 bg-paper px-3 py-2 text-sm">
                <input
                  type="checkbox"
                  checked={checked}
                  onChange={() =>
                    setSelected((prev) =>
                      prev.includes(h.id) ? prev.filter((id) => id !== h.id) : [...prev, h.id],
                    )
                  }
                  className="h-4 w-4"
                />
                <span className="font-semibold">{h.honey_type || "Honey"}</span>
                <span className="text-muted">{fmtNum(h.quantity_kg, " kg")}</span>
                <span className="ml-auto text-muted">{fmtDate(h.harvested_at)}</span>
              </label>
            </li>
          );
        })}
      </ul>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <label className="text-sm">
          <span className="mb-1 block font-semibold">Batch code (optional)</span>
          <Input value={code} onChange={(e) => setCode(e.target.value)} placeholder="Auto-generated" />
        </label>
        <label className="text-sm">
          <span className="mb-1 block font-semibold">Origin (optional)</span>
          <Input value={origin} onChange={(e) => setOrigin(e.target.value)} placeholder="e.g. Nilgiri slopes" />
        </label>
      </div>
      <p className="mt-3 text-sm text-muted">
        Honey type {honeyType ? `“${honeyType}”` : "will follow the selected harvests"}; quantity is
        the sum of the selected harvests ({fmtNum(totalKg, " kg")}).
      </p>
      <Button type="button" className="mt-3" disabled={createBatch.isPending} onClick={() => void submit()}>
        {createBatch.isPending ? "Creating…" : "Create batch"}
      </Button>
    </Card>
  );
}



