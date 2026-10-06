import { Link } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { ChevronDown, ChevronRight } from "lucide-react";
import { PageHeader } from "@/components/hc/page-header";
import { HeroStatus, KpiCard } from "@/components/hc/kpi";
import { StatusBadge } from "@/components/hc/status-badge";
import { EmptyState, ErrorState, LoadingBlock, attentionSummary } from "@/components/hc/query-state";
import { Input } from "@/components/ui/input";
import { useHcQuery } from "@/lib/hc/query";
import { VanSubmodule } from "@/features/kvic/van-submodule";
import { asString, fmtNum } from "@/lib/hc/format";
import { ledgerExplanation, ledgerHeadline, readLedgerHealth } from "@/lib/hc/blockchain";
import type { OrganizationSummary } from "@/lib/hc/types";

export function KvicOverview() {
  const stats = useHcQuery(["platform", "stats"], (api) => api.platformStats());
  const orgs = useHcQuery(["platform", "orgs"], (api) => api.platformOrganizations());
  const notes = useHcQuery(["notifications"], (api) => api.notifications());
  const chain = useHcQuery(["chain", "health"], (api) => api.blockchainHealth());
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("all");
  const [openId, setOpenId] = useState<string | null>(null);

  const clusters = useMemo(() => {
    const rows = orgs.data || [];
    return rows.filter((org) => {
      const hay =
        `${asString(org.name, "")} ${asString(org.state, "")} ${asString(org.district, "")}`.toLowerCase();
      const matchQ = !q || hay.includes(q.toLowerCase());
      const st = asString(org.status, "").toLowerCase();
      const matchS = status === "all" || st === status;
      return matchQ && matchS;
    });
  }, [orgs.data, q, status]);

  // Both of these drive a claim that nothing is wrong. A denied request must
  // not be allowed to produce that claim, so the error states travel with them.
  const attention = (orgs.data || []).filter((o) => {
    const st = asString(o.status).toLowerCase();
    return st !== "" && st !== "active";
  });
  const orgsUnreadable = Boolean(orgs.error);
  const notesUnreadable = Boolean(notes.error);
  const unread = notesUnreadable ? undefined : (notes.data?.unread_count ?? 0);

  if (stats.loading && !stats.data) return <LoadingBlock label="Loading cluster status…" />;
  if (stats.error) return <ErrorState error={stats.error} onRetry={() => void stats.refetch()} />;
  if (!stats.data) return <EmptyState title="No platform statistics are available yet." />;

  const s = stats.data;
  const ledger = readLedgerHealth(chain.data);
  const clusterState = attentionSummary({
    count: attention.length,
    errored: orgsUnreadable,
    clean: "Clusters are operating without flagged issues",
    counted: (n) => `${n} cluster${n === 1 ? "" : "s"} need attention`,
  });

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="KVIC / Institution"
        title="Honey ecosystem status"
        description="Watch clusters, production, verification, and issues that need institutional attention. This is not a generic admin console."
      />

      <HeroStatus
        tone={clusterState.tone}
        title={clusterState.title}
        detail={
          unread === undefined
            ? "The alert count could not be read, so this view cannot confirm how many alerts are outstanding. Open a cluster to review members, hives, harvests, and laboratory status."
            : unread
              ? `${unread} alert${unread === 1 ? "" : "s"} require a look. Open a cluster to see members, hives, batches, and verification.`
              : "Open a cluster to review members, hives, harvests, and laboratory status."
        }
      />

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard level={1} label="Active organizations" value={fmtNum(s.organizations)} hint="FPOs and institutions on the platform" />
        <KpiCard label="Beekeepers" value={fmtNum(s.registered_beekeepers)} />
        <KpiCard label="Active hives" value={fmtNum(s.hives)} />
        <KpiCard label="Honey harvested" value={fmtNum(s.honey_harvested_kg, " kg")} />
      </div>
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard level={3} label="Batches" value={fmtNum(s.batches)} hint={trustHint(s.batch_trust)} />
        <KpiCard level={3} label="Lab tests" value={fmtNum(s.lab_tests)} />
        <KpiCard level={3} label="IoT devices" value={fmtNum(s.iot_devices)} />
        <KpiCard
          level={3}
          label="Ledger"
          value={ledgerHeadline(ledger)}
          hint={ledgerExplanation(ledger)}
        />
      </div>

      {/* Mobile processing van — a submodule of this surface, not a portal. */}
      <VanSubmodule />

      <section>
        <div className="mb-4 flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
          <div>
            <h2 className="font-display text-2xl">Cluster management</h2>
            <p className="mt-1 text-sm text-muted">
              Compact cluster health. Expand a row for counts, then open the cluster for the full
              path from members to verification.
            </p>
          </div>
          <div className="flex w-full flex-col gap-2 sm:flex-row md:w-auto">
            <Input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Search cluster or region"
              className="md:w-64"
            />
            <select
              className="h-11 rounded-xl border border-black/10 bg-paper px-3 text-sm"
              value={status}
              onChange={(e) => setStatus(e.target.value)}
              aria-label="Filter by status"
            >
              <option value="all">All statuses</option>
              <option value="active">Active</option>
              <option value="attention">Needs attention</option>
              <option value="onboarding">Onboarding</option>
            </select>
          </div>
        </div>

        {orgs.error ? (
          <ErrorState error={orgs.error} onRetry={() => void orgs.refetch()} />
        ) : orgs.loading ? (
          <LoadingBlock />
        ) : clusters.length === 0 ? (
          <EmptyState
            title="No organizations match these filters."
            detail="Clear the search or status filter to see every cluster."
          />
        ) : (
          <div className="space-y-3">
            {clusters.map((org) => (
              <ClusterRow
                key={org.id}
                org={org}
                open={openId === org.id}
                onToggle={() => setOpenId(openId === org.id ? null : org.id)}
              />
            ))}
          </div>
        )}
      </section>

      <section>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="font-display text-xl">Alerts requiring attention</h2>
          <Link to="/alerts" className="text-sm font-semibold text-grove-700">
            Open alerts
          </Link>
        </div>
        {notes.error ? (
          <ErrorState error={notes.error} onRetry={() => void notes.refetch()} />
        ) : notes.isPending ? (
          <LoadingBlock label="Loading alerts…" />
        ) : (notes.data?.items || []).filter((n) => !n.read).length === 0 ? (
          <EmptyState title="No unread institutional alerts." />
        ) : (
          <ul className="space-y-2">
            {(notes.data?.items || [])
              .filter((n) => !n.read)
              .slice(0, 5)
              .map((n) => (
                <li key={n.notification_id} className="rounded-2xl bg-paper p-4 shadow-[var(--shadow-card)]">
                  <p className="font-semibold">{n.title}</p>
                  <p className="mt-1 text-sm text-muted">{n.body}</p>
                </li>
              ))}
          </ul>
        )}
      </section>
    </div>
  );
}

function trustHint(trust?: Record<string, number>) {
  if (!trust) return "Verification mix as reported";
  const lab = trust.lab_verified ?? 0;
  const total = Object.values(trust).reduce((a, b) => a + b, 0);
  if (!total) return "No batch trust mix yet";
  return `${lab} of ${total} lab verified`;
}

function ClusterRow({
  org,
  open,
  onToggle,
}: {
  org: OrganizationSummary;
  open: boolean;
  onToggle: () => void;
}) {
  return (
    <article className="rounded-2xl bg-paper shadow-[var(--shadow-card)]">
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full items-center gap-3 p-4 text-left"
      >
        {open ? <ChevronDown size={18} /> : <ChevronRight size={18} />}
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            {/* No invented fallbacks: a name the API did not send reads as
                "Not available" rather than silently becoming an org id, and a
                missing status is not dressed up as "registered". */}
            <p className="font-display text-lg">{asString(org.name)}</p>
            <StatusBadge label={asString(org.status)} />
          </div>
          <p className="mt-1 text-sm text-muted">
            {asString(org.state)}
            {asString(org.district, "") ? ` / ${asString(org.district)}` : null}
            {asString(org.type, "") ? ` / ${asString(org.type)}` : null}
          </p>
        </div>
      </button>
      {open ? (
        <div className="border-t border-black/5 px-4 py-4">
          <dl className="grid gap-3 sm:grid-cols-3">
            <div>
              <dt className="text-xs text-muted">Location</dt>
              <dd className="font-semibold">
                {asString(org.location, "") || asString(org.address, "") || "Not recorded"}
              </dd>
            </div>
            <div>
              <dt className="text-xs text-muted">Registration no.</dt>
              <dd className="font-semibold">{asString(org.registration_no, "Not recorded")}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted">Contact</dt>
              <dd className="font-semibold">{asString(org.contact_email, "Not recorded")}</dd>
            </div>
          </dl>
          <Link
            to="/kvic/$orgId"
            params={{ orgId: org.id }}
            className="mt-4 inline-flex min-h-11 items-center font-semibold text-grove-700"
          >
            Open cluster
          </Link>
        </div>
      ) : null}
    </article>
  );
}
