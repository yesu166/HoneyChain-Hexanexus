import { Link, useParams } from "@tanstack/react-router";
import { useMemo } from "react";
import { PageHeader } from "@/components/hc/page-header";
import { HeroStatus, KpiCard } from "@/components/hc/kpi";
import { BatchCard } from "@/components/hc/batch-card";
import { DataTable } from "@/components/hc/data-table";
import { StatusBadge } from "@/components/hc/status-badge";
import { Timeline } from "@/components/hc/timeline";
import { EmptyState, ErrorState, LoadingBlock, attentionSummary } from "@/components/hc/query-state";
import { useHcQuery } from "@/lib/hc/query";
import { asString, fmtDate, fmtNum, isDeviceHealthy } from "@/lib/hc/format";
import type { LabTest } from "@/lib/hc/types";

/**
 * KVIC view of one cluster (FPO organization).
 *
 * The cluster dashboard endpoint returns flat KPI counters only — it does not
 * embed harvest, batch, lab-test, or device rows. Like the FPO workspace, this
 * page fetches the real lists it can read and scopes them client-side by
 * organization id. Nothing is invented for rows the API does not return.
 */
export function ClusterDetail() {
  const { orgId } = useParams({ strict: false }) as { orgId: string };

  const dash = useHcQuery(["org", orgId, "dashboard"], (api) => api.orgDashboard(orgId));
  const batches = useHcQuery(["batches"], (api) => api.batches());
  const devices = useHcQuery(["iot", "devices"], (api) => api.iotDevices());

  const orgBatches = useMemo(
    () => (batches.data || []).filter((b) => b.organization_id === orgId),
    [batches.data, orgId],
  );
  const batchKey = orgBatches.map((b) => b.id).sort().join(",");
  const orgDevices = useMemo(
    () => (devices.data || []).filter((d) => d.organization_id === orgId),
    [devices.data, orgId],
  );

  // Laboratory tests are listed per batch (GET /batches/{id}/lab-tests).
  //
  // A per-batch failure is collected rather than swallowed. Swallowing it as
  // `[]` made a 403 indistinguishable from "this batch has no tests", so a
  // pending-result batch could read as fully verified. The first real failure
  // is now surfaced so the page can refuse to confirm the cluster's status.
  const labTests = useHcQuery(
    ["kvic", orgId, "lab-tests", batchKey || "none"],
    async (api): Promise<LabTest[]> => {
      const results = await Promise.allSettled(orgBatches.map((b) => api.labTests(b.id)));
      const failure = results.find((r) => r.status === "rejected");
      if (failure && failure.status === "rejected") throw failure.reason;
      return results.flatMap((r) => (r.status === "fulfilled" ? r.value : []));
    },
    { enabled: Boolean(batchKey) },
  );

  if (dash.loading) return <LoadingBlock label="Loading cluster…" />;
  if (dash.error) return <ErrorState error={dash.error} onRetry={() => void dash.refetch()} />;
  if (!dash.data) return <EmptyState title="This organization has no dashboard data yet." />;

  const d = dash.data;
  const name = asString(d.org_name);
  const pendingTests = (labTests.data || []).filter((t) => !t.result);
  const badDevices = orgDevices.filter((dev) => !isDeviceHealthy(dev.device_status));
  const pending = d.pending_actions;

  // The three lists below are separate requests. This heading used to say
  // "all clear" whenever all three happened to be empty, which a single
  // denied request could produce. `batches.error` matters here even though
  // `dash` succeeded: without it, orgBatches is [] and the page quietly
  // reports a cluster with no batches and nothing pending.
  const batchesUnreadable = Boolean(batches.error);
  const testsUnreadable = Boolean(labTests.error);
  const devicesUnreadable = Boolean(devices.error);
  const unreadable = batchesUnreadable || testsUnreadable || devicesUnreadable;
  // The API's own pending_actions counter is part of this total. Leaving it out
  // was its own false all-clear: a cluster reporting 4 pending actions with no
  // pending lab tests and no flagged devices fell through to "no pending
  // cluster actions".
  const dashboardPending = Number(d.pending_actions) || 0;
  const pendingCount = dashboardPending + pendingTests.length + badDevices.length;
  const state = attentionSummary({
    count: pendingCount,
    errored: unreadable,
    clean: "No pending cluster actions",
    counted: (n) =>
      `${dashboardPending} dashboard item${dashboardPending === 1 ? "" : "s"} · ${n - dashboardPending} lab test or device issue${n - dashboardPending === 1 ? "" : "s"}`,
  });


  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Cluster"
        title={name}
        description={`Reported by HoneyChain${d.source ? ` (${d.source})` : ""} · ${pending} pending actions`}
        action={
          <Link to="/kvic" className="text-sm font-semibold text-grove-700">
            All clusters
          </Link>
        }
      />
      <HeroStatus
        tone={state.tone}
        title={state.title}
        detail={
          unreadable
            ? `Members, hives, harvests, batches, and laboratory status for this cluster, as reported by HoneyChain. Some of those lists could not be read, so this summary may be incomplete.`
            : "Members, hives, harvests, batches, and laboratory status for this cluster, as reported by HoneyChain."
        }
      />
      {unreadable ? (
        <ErrorState
          error={batches.error || labTests.error || devices.error}
          onRetry={() => {
            void batches.refetch();
            void labTests.refetch();
            void devices.refetch();
          }}
        />
      ) : null}
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard label="Beekeepers" value={fmtNum(d.active_beekeepers)} />
        <KpiCard label="Hives" value={fmtNum(d.hives)} />
        <KpiCard label="Honey harvested" value={fmtNum(d.honey_harvested_kg, " kg")} />
        <KpiCard
          label="Verified batches"
          value={`${fmtNum(d.verified_batches)} / ${fmtNum(d.batches)}`}
        />
      </div>

      <section>
        <h2 className="mb-3 font-display text-xl">Batches and verification</h2>
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
          <EmptyState title="No batches have been created in this cluster yet." />
        )}
      </section>

      <section>
        <h2 className="mb-3 font-display text-xl">Laboratory queue</h2>
        {labTests.error ? (
          <ErrorState error={labTests.error} onRetry={() => void labTests.refetch()} />
        ) : labTests.loading ? (
          <LoadingBlock label="Loading laboratory tests…" />
        ) : (
          <DataTable
            empty="No laboratory tests are pending for this cluster."
            columns={[
              { key: "batch", label: "Batch" },
              { key: "status", label: "Status" },
              { key: "note", label: "Test" },
            ]}
            rows={pendingTests.map((t) => ({
              batch: t.batch_code || t.batch_id,
              status: <StatusBadge label={t.status} />,
              note: t.requested_note || "Not specified",
            }))}
          />
        )}
      </section>

      <section>
        <h2 className="mb-3 font-display text-xl">Devices</h2>
        {devices.error ? (
          <ErrorState error={devices.error} onRetry={() => void devices.refetch()} />
        ) : devices.loading ? (
          <LoadingBlock label="Loading devices…" />
        ) : (
          <DataTable
            empty="No IoT devices are assigned to this cluster."
            columns={[
              { key: "name", label: "Device" },
              { key: "status", label: "Status" },
              { key: "seen", label: "Last seen" },
            ]}
            rows={orgDevices.map((dev) => ({
              name: dev.device_name,
              status: <StatusBadge label={dev.device_status} />,
              seen: fmtDate(dev.last_seen ?? undefined),
            }))}
          />
        )}
      </section>

      <section>
        <h2 className="mb-2 font-display text-xl">Recent cluster activity</h2>
        <Timeline
          items={(d.recent_activity || []).map((a) => ({
            title: asString(a.label, asString(a.type, "Activity")),
            at: asString(a.timestamp, ""),
          }))}
        />
      </section>
    </div>
  );
}
