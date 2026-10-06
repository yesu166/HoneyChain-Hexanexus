import { PageHeader } from "@/components/hc/page-header";
import { HeroStatus, KpiCard } from "@/components/hc/kpi";
import { LedgerPanel } from "@/components/hc/ledger-panel";
import { DataTable } from "@/components/hc/data-table";
import { StatusBadge } from "@/components/hc/status-badge";
import { Timeline } from "@/components/hc/timeline";
import { EmptyState, ErrorState, LoadingBlock, attentionSummary } from "@/components/hc/query-state";
import { Card } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useHcQuery } from "@/lib/hc/query";
import { asString, fmtNum, isDeviceHealthy } from "@/lib/hc/format";
import { ledgerHeadline, readLedgerHealth } from "@/lib/hc/blockchain";

export function AdminWorkspace({ panel = "business" }: { panel?: "business" | "platform" }) {
  const stats = useHcQuery(["platform", "stats"], (api) => api.platformStats());
  const orgs = useHcQuery(["platform", "orgs"], (api) => api.platformOrganizations());
  // HoneyChain exposes platform-wide beekeeper membership (`/platform/beekeepers`);
  // there is no "list all users" endpoint, so that is what this table shows.
  const beekeepers = useHcQuery(["platform", "beekeepers"], (api) => api.platformBeekeepers());
  const audit = useHcQuery(["platform", "audit"], (api) => api.platformAudit());
  const health = useHcQuery(["health"], (api) => api.health());
  // `/blockchain/health` is public on HoneyChain, so ledger state is readable even
  // when the operator's role cannot read the authenticated status route.
  const chain = useHcQuery(["chain", "health"], (api) => api.blockchainHealth());
  const devices = useHcQuery(["iot"], (api) => api.iotDevices());
  const notes = useHcQuery(["notifications"], (api) => api.notifications());

  if (stats.loading && !stats.data) return <LoadingBlock label="Loading platform operations…" />;
  if (stats.error) return <ErrorState error={stats.error} onRetry={() => void stats.refetch()} />;

  // `unread ?? 0` would turn a denied notifications request into "0 alerts", and
  // this heading claims no alerts exist. An unreadable input yields "could not
  // be confirmed" instead of a clean bill of health.
  const notesUnreadable = Boolean(notes.error);
  const devicesUnreadable = Boolean(devices.error);
  const unread = notesUnreadable ? undefined : (notes.data?.unread_count ?? 0);
  const offline = (devices.data || []).filter((d) => !isDeviceHealthy(d.device_status));
  const ledger = readLedgerHealth(chain.data);
  const opState = attentionSummary({
    count: (unread || 0) + offline.length,
    errored: notesUnreadable || devicesUnreadable,
    clean: "No operational alerts in this view",
    counted: () => {
      const alertPart = unread === undefined ? "alerts unknown" : `${unread} alert${unread === 1 ? "" : "s"}`;
      return `${alertPart} · ${offline.length} device${offline.length === 1 ? "" : "s"} need attention`;
    },
  });

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Platform administrator"
        title={panel === "platform" ? "System operations" : "Business operations"}
        description="Business activity and system health are kept apart. Demo tamper controls are not exposed here."
      />
      <HeroStatus
        tone={opState.tone}
        title={opState.title}
        detail={`Every figure below comes from HoneyChain. ${ledgerHeadline(ledger)}. A connected ledger adapter is not a purity claim.`}
      />

      {notesUnreadable || devicesUnreadable ? (
        <ErrorState
          error={notes.error || devices.error}
          onRetry={() => {
            void notes.refetch();
            void devices.refetch();
          }}
        />
      ) : null}

      <Tabs defaultValue={panel}>
        <TabsList>
          <TabsTrigger value="business">Business operations</TabsTrigger>
          <TabsTrigger value="platform">System / platform</TabsTrigger>
        </TabsList>
        <TabsContent value="business">
          {/* Counts are read straight from GET /api/v1/platform/stats. There is
              no client-side seed and no fallback number: an absent field would
              render as "Not available" rather than as zero-by-coincidence. */}
          <div className="grid gap-3 sm:grid-cols-3">
            <KpiCard
              label="Beekeepers"
              value={fmtNum(stats.data?.registered_beekeepers)}
              hint="GET /api/v1/platform/stats"
            />
            <KpiCard
              label="Organizations"
              value={fmtNum(stats.data?.organizations)}
              hint="GET /api/v1/platform/stats"
            />
            <KpiCard
              label="Batches"
              value={fmtNum(stats.data?.batches)}
              hint="GET /api/v1/platform/stats"
            />
          </div>
          <section className="mt-6">
            <h2 className="mb-3 font-display text-xl">Registered beekeepers</h2>
            {beekeepers.loading ? (
              <LoadingBlock label="Loading beekeepers…" />
            ) : beekeepers.error ? (
              // A 403 is a permission answer, not an empty list. Rendering it as
              // "no beekeepers were returned" would misreport the platform.
              <ErrorState error={beekeepers.error} onRetry={() => void beekeepers.refetch()} />
            ) : (
              <DataTable
                empty="No beekeepers were returned by the platform API."
                columns={[
                  { key: "name", label: "Name" },
                  { key: "email", label: "Email" },
                  { key: "role", label: "Role" },
                  { key: "org", label: "Organization" },
                ]}
                rows={(beekeepers.data || []).map((u) => ({
                  name: u.name,
                  email: u.email,
                  role: <StatusBadge label={u.role} />,
                  org: u.org_id || "Not available",
                }))}
              />
            )}
          </section>
          <section className="mt-6">
            <h2 className="mb-3 font-display text-xl">Organizations</h2>
            {orgs.loading ? (
              <LoadingBlock label="Loading organizations…" />
            ) : orgs.error ? (
              <ErrorState error={orgs.error} onRetry={() => void orgs.refetch()} />
            ) : (
              <DataTable
                empty="No organizations were returned."
                columns={[
                  { key: "name", label: "Name" },
                  { key: "status", label: "Status" },
                  { key: "state", label: "State" },
                ]}
                rows={(orgs.data || []).map((o) => ({
                  name: asString(o.name, o.id),
                  status: <StatusBadge label={asString(o.status)} />,
                  state: asString(o.state),
                }))}
              />
            )}
          </section>
        </TabsContent>
        <TabsContent value="platform">
          <div className="grid gap-4 md:grid-cols-2">
            <Card>
              <h2 className="font-display text-xl">API status</h2>
              {health.error ? (
                <ErrorState error={health.error} onRetry={() => void health.refetch()} />
              ) : health.data ? (
                <dl className="mt-3 space-y-2 text-sm">
                  <div>Status: {asString(health.data.status)}</div>
                  <div>Service: {asString(health.data.service)}</div>
                  {typeof health.data.mode === "string" ? (
                    <div>Mode: {health.data.mode}</div>
                  ) : null}
                  {typeof health.data.note === "string" ? <div>{health.data.note}</div> : null}
                </dl>
              ) : (
                <EmptyState title="No health payload returned." />
              )}
            </Card>
            <LedgerPanel
              payload={chain.data}
              error={chain.error}
              loading={chain.loading}
              onRetry={() => void chain.refetch()}
            />
          </div>
          <section className="mt-6">
            <h2 className="mb-3 font-display text-xl">IoT fleet</h2>
            <DataTable
              empty="No IoT devices were returned."
              columns={[
                { key: "name", label: "Device" },
                { key: "status", label: "Status" },
                { key: "org", label: "Organization" },
              ]}
              rows={(devices.data || []).map((d) => ({
                name: d.device_name,
                status: <StatusBadge label={d.device_status} />,
                org: d.organization_id,
              }))}
            />
          </section>
          <section className="mt-6">
            <h2 className="mb-3 font-display text-xl">What changed</h2>
            {audit.error ? (
              <ErrorState error={audit.error} onRetry={() => void audit.refetch()} />
            ) : (
              <Timeline
                items={(audit.data || []).slice(0, 12).map((row) => ({
                  title: asString(row.action, "Audit event"),
                  at: asString(row.created_at, ""),
                  detail: `${asString(row.actor_role, "")} → ${asString(row.target_type, "")} ${asString(row.target_key, "")}`,
                }))}
              />
            )}
          </section>
        </TabsContent>
      </Tabs>
    </div>
  );
}
