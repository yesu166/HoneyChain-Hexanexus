import { useMemo, useState } from "react";
import { toast } from "sonner";
import { HeroStatus, KpiCard } from "@/components/hc/kpi";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/hc/query-state";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";
import { ListingRow, OrderRow } from "@/features/market/market-rows";
import { useHcMutation, useHcQuery } from "@/lib/hc/query";
import { describeApiError } from "@/lib/hc/client";

/**
 * FPO Market Linkage — a CAPABILITY of the FPO workspace, not a portal.
 *
 * There is deliberately no "Market Linkage" card in the workspace catalog; this
 * lives inside the FPO workspace because that is who acts on it.
 *
 * Every figure is read back from the API after a write. `remaining_kg` in
 * particular is whatever the backend stored: it decrements when a seller accepts
 * an order, and this component refetches rather than adjusting it locally, so
 * the screen can never show more stock available than the ledger has actually
 * committed away.
 */
export function MarketLinkagePanel() {
  const batches = useHcQuery(["batches"], (api) => api.batches());
  const listings = useHcQuery(["market", "listings"], (api) => api.marketListings());
  const orders = useHcQuery(["market", "orders"], (api) => api.purchaseOrders());

  const [batchId, setBatchId] = useState("");
  const [quantity, setQuantity] = useState("");
  const [price, setPrice] = useState("");

  // Only laboratory-verified lots are offered. The API enforces this too; the
  // filter stops the operator being invited to attempt an illegal listing.
  const sellable = useMemo(
    () =>
      (batches.data || []).filter(
        (b) => b.trust_tier === "lab_verified" || b.trust_tier === "blockchain_anchored",
      ),
    [batches.data],
  );

  // Accepting an order changes both the committed stock and the order's status,
  // so both lists (plus the seller's inbox) are invalidated together.
  const invalidate = [["market", "listings"], ["market", "orders"], ["notifications"]];

  const createListing = useHcMutation(
    (api, body: { batch_id: string; quantity_kg: number; price_per_kg: number }) =>
      api.createListing(body),
    invalidate,
  );
  const decide = useHcMutation(
    (api, input: { id: string; accept: boolean }) => api.decideOrder(input.id, input.accept),
    invalidate,
  );
  const withdraw = useHcMutation((api, id: string) => api.withdrawListing(id), invalidate);

  const inbound = orders.data || [];
  const openListings = (listings.data || []).filter((l) => l.status === "OPEN");
  const committedKg = openListings.reduce((sum, l) => sum + (l.remaining_kg || 0), 0);
  const pending = inbound.filter((o) => o.status === "REQUESTED");

  if (listings.loading || orders.loading) {
    return <LoadingBlock label="Loading market linkage…" />;
  }
  if (listings.error) {
    return (
      <ErrorState error={listings.error} onRetry={() => void listings.refetch()} />
    );
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    const kg = Number(quantity);
    const perKg = Number(price);
    if (!batchId || !(kg > 0) || !(perKg > 0)) {
      toast.error("Choose a batch and enter a quantity and price above zero.");
      return;
    }
    createListing.mutate(
      { batch_id: batchId, quantity_kg: kg, price_per_kg: perKg },
      {
        onSuccess: () => {
          toast.success("Listed for sale.");
          setBatchId("");
          setQuantity("");
          setPrice("");
        },
        // The backend's own message, never an invented one: an unverified batch
        // or an oversize request must surface exactly what the API said.
        onError: (err) => toast.error(describeApiError(err).detail),
      },
    );
  }
  return (
    <div className="space-y-5">
      <HeroStatus
        tone={pending.length ? "warn" : "ok"}
        title={
          pending.length
            ? `${pending.length} purchase request${pending.length === 1 ? "" : "s"} awaiting your decision`
            : "No purchase requests waiting"
        }
        detail="Only a laboratory-verified batch can be listed. Buyers request a quantity; you accept or reject, and fulfilment records a real sale on the batch."
      />
      <div className="grid gap-3 sm:grid-cols-2">
        <KpiCard
          label="Open listings"
          value={String(openListings.length)}
          hint="Lots currently offered to buyers."
        />
        <KpiCard
          label="Stock still available"
          value={`${committedKg} kg`}
          hint="Remaining kilograms across open listings, as the API records them."
        />
      </div>

      <Card className="p-4">
        <h3 className="font-display text-lg">List a verified batch</h3>
        {sellable.length ? (
          <form onSubmit={submit} className="mt-3 grid gap-3 sm:grid-cols-4">
            <label className="text-sm">
              Batch
              <select
                className="mt-1 w-full rounded-xl border border-cream bg-paper px-3 py-2"
                value={batchId}
                onChange={(e) => setBatchId(e.target.value)}
              >
                <option value="">Select a lot…</option>
                {sellable.map((b) => (
                  <option key={b.id} value={b.id}>
                    {b.batch_code} · {b.quantity_kg} kg
                  </option>
                ))}
              </select>
            </label>
            <label className="text-sm">
              Quantity (kg)
              <Input
                className="mt-1"
                value={quantity}
                onChange={(e) => setQuantity(e.target.value)}
                inputMode="decimal"
              />
            </label>
            <label className="text-sm">
              Price per kg
              <Input
                className="mt-1"
                value={price}
                onChange={(e) => setPrice(e.target.value)}
                inputMode="decimal"
              />
            </label>
            <div className="flex items-end">
              <Button type="submit" disabled={createListing.isPending}>
                {createListing.isPending ? "Listing…" : "List for sale"}
              </Button>
            </div>
          </form>
        ) : (
          <p className="mt-2 text-sm text-muted">
            No laboratory-verified batch is available to list. A lot must pass
            laboratory testing before it can be offered for sale.
          </p>
        )}
      </Card>

      <section>
        <h3 className="mb-2 font-display text-xl">Purchase requests</h3>
        {inbound.length ? (
          <div className="space-y-2">
            {inbound.map((o) => (
              <OrderRow
                key={o.id}
                order={o}
                role="seller"
                busy={decide.isPending}
                onDecide={(accept) =>
                  decide.mutate(
                    { id: o.id, accept },
                    {
                      onSuccess: () =>
                        toast.success(accept ? "Order accepted." : "Order declined."),
                      onError: (err) => toast.error(describeApiError(err).detail),
                    },
                  )
                }
              />
            ))}
          </div>
        ) : (
          <EmptyState
            title="No purchase requests yet."
            detail="Buyers who find one of your lots will request it here."
          />
        )}
      </section>

      <section>
        <h3 className="mb-2 font-display text-xl">Your listings</h3>
        {(listings.data || []).length ? (
          <div className="space-y-2">
            {(listings.data || []).map((l) => (
              <ListingRow
                key={l.id}
                listing={l}
                busy={withdraw.isPending}
                onWithdraw={() =>
                  withdraw.mutate(l.id, {
                    onSuccess: () => toast.success("Listing withdrawn."),
                    onError: (err) => toast.error(describeApiError(err).detail),
                  })
                }
              />
            ))}
          </div>
        ) : (
          <EmptyState title="You have not listed any batches." />
        )}
      </section>
    </div>
  );
}
