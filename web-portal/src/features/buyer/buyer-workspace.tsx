import { useState } from "react";
import { toast } from "sonner";
import { PageHeader } from "@/components/hc/page-header";
import { HeroStatus, KpiCard } from "@/components/hc/kpi";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/hc/query-state";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ListingRow, OrderRow } from "@/features/market/market-rows";
import { useHcMutation, useHcQuery } from "@/lib/hc/query";
import { describeApiError } from "@/lib/hc/client";

/**
 * Buyer / Procurement — a CAPABILITY of the Buyer workspace, not a portal.
 *
 * This replaced a read-only "available lots" browser. The buyer is now an
 * active participant in a real transaction: it requests a quantity against an
 * open listing, the seller accepts or rejects, and fulfilling an accepted order
 * writes a SALE custody event onto the batch — so the purchase history shown
 * here is backed by the same provenance ledger the passport reads.
 *
 * Quantities are validated server-side against `remaining_kg`, so this screen
 * deliberately does not pre-compute "can I still buy X" — it sends the request
 * and reports exactly what the API decided.
 */
export function BuyerWorkspace() {
  const market = useHcQuery(["market", "marketplace"], (api) => api.marketplace());
  const [requesting, setRequesting] = useState<{
    listingId: string;
    remaining: number;
    batchCode: string;
  } | null>(null);
  const [quantity, setQuantity] = useState("");

  const invalidate = [
    ["market", "marketplace"],
    ["market", "orders"],
    ["notifications"],
  ];

  const createOrder = useHcMutation(
    (api, body: { listing_id: string; quantity_kg: number }) => api.createOrder(body),
    invalidate,
  );
  const fulfil = useHcMutation((api, id: string) => api.fulfilOrder(id), invalidate);
  const cancel = useHcMutation((api, id: string) => api.cancelOrder(id), invalidate);

  const listings = market.data?.listings || [];
  const orders = market.data?.orders || [];
  const inFlight = orders.filter((o) => o.status === "REQUESTED");
  const accepted = orders.filter((o) => o.status === "ACCEPTED");
  const history = orders.filter(
    (o) => o.status === "FULFILLED" || o.status === "REJECTED" || o.status === "CANCELLED",
  );

  if (market.loading) return <LoadingBlock label="Loading available lots…" />;
  if (market.error) {
    return <ErrorState error={market.error} onRetry={() => void market.refetch()} />;
  }

  function submitRequest(e: React.FormEvent) {
    e.preventDefault();
    if (!requesting) return;
    const kg = Number(quantity);
    if (!(kg > 0)) {
      toast.error("Enter a quantity greater than zero.");
      return;
    }
    createOrder.mutate(
      { listing_id: requesting.listingId, quantity_kg: kg },
      {
        onSuccess: () => {
          toast.success("Purchase requested. The seller must accept it.");
          setRequesting(null);
          setQuantity("");
        },
        // The API refusal (e.g. more kilograms than remain) is surfaced
        // verbatim rather than replaced with a generic message.
        onError: (err) => toast.error(describeApiError(err).detail),
      },
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Buyer"
        title="Procurement"
        description="Open lots from verified sellers. Request a quantity, then fulfil once the seller accepts — the sale is recorded on the batch's custody history."
      />
      <HeroStatus
        tone={inFlight.length || accepted.length ? "warn" : "ok"}
        title={
          accepted.length
            ? `${accepted.length} accepted order${accepted.length === 1 ? "" : "s"} ready to fulfil`
            : inFlight.length
              ? `${inFlight.length} request${inFlight.length === 1 ? "" : "s"} awaiting the seller`
              : "No open requests"
        }
        detail="Quantities are committed when a seller accepts, not when you request. A fulfilled order writes a real sale event to the batch."
      />
      <div className="grid gap-3 sm:grid-cols-3">
        <KpiCard label="Open lots" value={String(listings.length)} hint="Verified batches currently offered." />
        <KpiCard label="Awaiting seller" value={String(inFlight.length)} hint="Your requests still to be decided." />
        <KpiCard label="Fulfilled" value={String(orders.filter((o) => o.status === "FULFILLED").length)} hint="Sales recorded on the batch." />
      </div>

      <section>
        <h2 className="mb-2 font-display text-xl">Open lots</h2>
        {listings.length ? (
          <div className="space-y-2">
            {listings.map((l) => (
              <ListingRow
                key={l.id}
                listing={l}
                onRequest={() => {
                  setRequesting({
                    listingId: l.id,
                    remaining: l.remaining_kg,
                    batchCode: l.batch_code || l.batch_id,
                  });
                  setQuantity("");
                }}
              />
            ))}
          </div>
        ) : (
          <EmptyState
            title="No open lots right now."
            detail="Sellers list a batch once it has passed laboratory verification."
          />
        )}
      </section>

      {requesting ? (
        <form onSubmit={submitRequest} className="rounded-2xl border border-cream bg-paper p-4">
          <h3 className="font-display text-lg">Request from {requesting.batchCode}</h3>
          <p className="text-sm text-muted">
            {requesting.remaining} kg remain on this listing. The seller decides whether to accept.
          </p>
          <div className="mt-3 flex flex-wrap items-end gap-3">
            <label className="text-sm">
              Quantity (kg)
              <Input
                className="mt-1 w-40"
                value={quantity}
                onChange={(e) => setQuantity(e.target.value)}
                inputMode="decimal"
              />
            </label>
            <Button type="submit" disabled={createOrder.isPending}>
              {createOrder.isPending ? "Sending…" : "Send request"}
            </Button>
            <Button
              type="button"
              variant="secondary"
              onClick={() => {
                setRequesting(null);
                setQuantity("");
              }}
            >
              Cancel
            </Button>
          </div>
        </form>
      ) : null}

      <section>
        <h2 className="mb-2 font-display text-xl">Your requests</h2>
        {orders.length ? (
          <div className="space-y-2">
            {orders.map((o) => (
              <div key={o.id}>
                <OrderRow order={o} role="buyer" />
                <div className="mt-1 flex gap-2 px-1">
                  {o.status === "ACCEPTED" ? (
                    <Button
                      size="sm"
                      disabled={fulfil.isPending}
                      onClick={() =>
                        fulfil.mutate(o.id, {
                          onSuccess: () =>
                            toast.success(
                              "Order fulfilled — the sale is on the batch's custody record.",
                            ),
                          onError: (err) => toast.error(describeApiError(err).detail),
                        })
                      }
                    >
                      Fulfill order
                    </Button>
                  ) : null}
                  {o.status === "REQUESTED" ? (
                    <Button
                      size="sm"
                      variant="secondary"
                      disabled={cancel.isPending}
                      onClick={() =>
                        cancel.mutate(o.id, {
                          onSuccess: () => toast.success("Request cancelled."),
                          onError: (err) => toast.error(describeApiError(err).detail),
                        })
                      }
                    >
                      Cancel request
                    </Button>
                  ) : null}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <EmptyState title="You have not requested any lots yet." />
        )}
      </section>

      {history.length ? (
        <section>
          <h2 className="mb-2 font-display text-xl">Decision history</h2>
          <div className="space-y-2">
            {history.map((o) => (
              <OrderRow key={o.id} order={o} role="buyer" />
            ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}
