import { AlertTriangle, Link2, ShieldCheck } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { ErrorState } from "@/components/hc/query-state";
import {
  anchorLabel,
  anchorTone,
  anchorVerdict,
  ledgerExplanation,
  ledgerHeadline,
  ledgerTone,
  readLedgerHealth,
  realTxId,
  type LedgerHealth,
} from "@/lib/hc/blockchain";

/**
 * The single blockchain surface for the whole portal.
 *
 * It prints only what HoneyChain returned. When the backend is on the development
 * ledger it says so in plain language, because "Ledger anchor confirmed" over
 * an in-process map is exactly the kind of claim a traceability product must
 * never make.
 */
export function LedgerPanel({
  payload,
  error,
  onRetry,
  loading,
}: {
  payload: unknown;
  error?: unknown;
  onRetry?: () => void;
  loading?: boolean;
}) {
  if (error) {
    return (
      <Card>
        <h2 className="font-display text-xl">Blockchain</h2>
        <div className="mt-3">
          <ErrorState error={error} onRetry={onRetry} />
        </div>
      </Card>
    );
  }

  const health: LedgerHealth | null = payload ? readLedgerHealth(payload) : null;
  const tone = ledgerTone(health);

  return (
    <Card>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="font-display text-xl">Blockchain</h2>
        <Badge tone={tone}>
          {loading && !health ? "Checking…" : (health?.kind ?? "UNAVAILABLE")}
        </Badge>
      </div>

      {health ? (
        <>
          <p className="mt-3 text-sm font-semibold text-ink">{ledgerHeadline(health)}</p>
          <p className="mt-2 text-xs leading-5 text-muted">{ledgerExplanation(health)}</p>

          {/* Only fields the backend actually returned are shown. */}
          <dl className="mt-4 grid gap-2 text-xs sm:grid-cols-2">
            {health.network ? <Field label="Network" value={health.network} /> : null}
            {health.channel ? <Field label="Channel" value={health.channel} /> : null}
            {health.chaincode ? (
              <Field
                label="Chaincode"
                value={
                  health.chaincodeVersion
                    ? `${health.chaincode} v${health.chaincodeVersion}`
                    : health.chaincode
                }
              />
            ) : null}
            {health.peer ? <Field label="Peer" value={health.peer} /> : null}
            {health.mspId ? <Field label="MSP" value={health.mspId} /> : null}
            {health.lastVerifiedAt ? (
              <Field label="Last verified" value={health.lastVerifiedAt} />
            ) : null}
          </dl>

          {!health.distributed ? (
            <p className="mt-4 flex items-start gap-2 rounded-xl bg-honey-50 p-3 text-[11px] leading-5 text-honey-600">
              <AlertTriangle size={14} className="mt-0.5 shrink-0" />
              <span>
                No distributed ledger is backing this API, so this portal cannot show a real
                transaction id. Anchors would be written to process memory only.
              </span>
            </p>
          ) : null}
        </>
      ) : (
        <p className="mt-3 text-sm text-muted">
          {loading ? "Asking HoneyChain for ledger status…" : "HoneyChain returned no ledger status."}
        </p>
      )}
    </Card>
  );
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg bg-cream px-2.5 py-1.5">
      <dt className="text-[10px] font-bold tracking-[0.1em] text-muted uppercase">{label}</dt>
      <dd className="mt-0.5 break-all font-medium text-ink">{value}</dd>
    </div>
  );
}

/**
 * The per-batch anchor state. Renders the real transaction id when the backend
 * supplied one and an explicit absence when it did not — never a placeholder
 * hash, block number or ledger height.
 */
export function AnchorStatus({
  anchor,
  health,
  compact = false,
  healthUnreadable = false,
}: {
  anchor: { chain_status?: string; tx_hash?: string } | null | undefined;
  health?: LedgerHealth | null;
  compact?: boolean;
  /** The ledger health request failed, so `health` being null is not evidence. */
  healthUnreadable?: boolean;
}) {
  const verdict = anchorVerdict(anchor);
  const tx = realTxId(anchor);
  const label = anchorLabel(verdict, health ?? null, healthUnreadable);

  return (
    <div className="space-y-2">
      <Badge tone={anchorTone(verdict)}>
        {verdict === "ANCHORED" ? <ShieldCheck size={12} /> : null}
        {label}
      </Badge>

      {tx ? (
        <p className="flex items-start gap-1.5 break-all text-[11px] text-muted">
          <Link2 size={12} className="mt-0.5 shrink-0" />
          <span className="font-mono">{tx}</span>
        </p>
      ) : verdict === "ANCHORED" ? (
        <p className="text-[11px] text-muted">
          The backend reported an anchor but returned no transaction id, so none is shown.
        </p>
      ) : !compact ? (
        <p className="text-[11px] text-muted">
          {health && !health.distributed
            ? "This deployment writes anchors to the development ledger, not to a distributed network."
            : "HoneyChain reports no confirmed ledger anchor for this lot."}
        </p>
      ) : null}
    </div>
  );
}
