import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/hc/status-badge";
import type { MarketListing, PurchaseOrder } from "@/lib/hc/types";

/**
 * Shared presentational rows for market linkage.
 *
 * Both the FPO seller view and the Buyer procurement view render these, so a
 * listing looks and reads the same on either side of a transaction.
 *
 * `remaining_kg` is always the figure the API returned. Neither component
 * computes or optimistically adjusts it — committed stock is decided on the
 * server when a seller accepts an order, so a local guess would be able to
 * disagree with the real ledger.
 */

export function OrderRow({
  order,
  role,
  onDecide,
  busy,
}: {
  order: PurchaseOrder;
  role: "seller" | "buyer";
  onDecide?: (accept: boolean) => void;
  busy?: boolean;
}) {
  return (
    <div className="rounded-2xl border border-cream bg-paper p-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="font-medium">
            {order.batch_code || order.batch_id} · {order.quantity_kg} kg
          </p>
          <p className="text-xs text-muted">
            {order.currency} {order.total_amount} total · requested {order.requested_at}
            {order.seller_org_id ? ` · seller ${order.seller_org_id}` : ""}
          </p>
          {order.seller_notes ? (
            <p className="mt-1 text-xs text-muted">Seller note: {order.seller_notes}</p>
          ) : null}
        </div>
        <StatusBadge label={order.status} />
      </div>
      {role === "seller" && order.status === "REQUESTED" && onDecide ? (
        <div className="mt-2 flex gap-2">
          <Button size="sm" disabled={busy} onClick={() => onDecide(true)}>
            Accept
          </Button>
          <Button
            size="sm"
            variant="secondary"
            disabled={busy}
            onClick={() => onDecide(false)}
          >
            Decline
          </Button>
        </div>
      ) : null}
    </div>
  );
}

export function ListingRow({
  listing,
  onWithdraw,
  onRequest,
  busy,
}: {
  listing: MarketListing;
  onWithdraw?: () => void;
  onRequest?: () => void;
  busy?: boolean;
}) {
  const committed = listing.quantity_kg - listing.remaining_kg;
  return (
    <div className="rounded-2xl border border-cream bg-paper p-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="font-medium">
            {listing.batch_code || listing.batch_id} · {listing.currency}{" "}
            {listing.price_per_kg}/kg
          </p>
          <p className="text-xs text-muted">
            {listing.batch_origin || "Origin not recorded"} ·{" "}
            <span className="font-medium">
              {listing.remaining_kg} kg of {listing.quantity_kg} kg remaining
            </span>
            {committed > 0 ? ` (${committed} kg committed)` : ""}
          </p>
          {listing.notes ? <p className="mt-1 text-xs text-muted">{listing.notes}</p> : null}
        </div>
        <div className="flex items-center gap-2">
          <StatusBadge label={listing.status} />
          {onRequest && listing.status === "OPEN" && listing.remaining_kg > 0 ? (
            <Button size="sm" disabled={busy} onClick={onRequest}>
              Request
            </Button>
          ) : null}
          {onWithdraw && listing.status === "OPEN" ? (
            <Button size="sm" variant="secondary" disabled={busy} onClick={onWithdraw}>
              Withdraw
            </Button>
          ) : null}
        </div>
      </div>
    </div>
  );
}