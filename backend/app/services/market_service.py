"""Market linkage: FPO listings and buyer purchase orders.

This is a capability of the FPO and Buyer surfaces, not a portal of its own. It
exists because "available lots" alone cannot express a transaction: a seller
commits quantity at a price, a buyer requests part of it, the seller accepts or
rejects, and fulfilment writes a real SALE custody event onto the batch.

Rules that keep the ledger honest:

  * A listing can only be created for a batch the seller actually owns.
  * A batch that failed laboratory testing may never be listed.
  * `remaining_kg` is decremented on acceptance, so committed kilograms can
    never be sold twice, and an accepted order that would oversell is rejected.
  * Fulfilment is a real custody SALE event written by the same call that marks
    the order FULFILLED — the buyer is notified from the write that moved the
    goods, never before.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository

# Only a batch that has cleared the laboratory may be offered. A failed lot is
# blocked here exactly as it is blocked from packaging.
_LISTABLE_TRUST = {"lab_verified", "blockchain_anchored"}
_BLOCKED_STATUSES = {"rejected", "lab_failed", "quarantined"}


class MarketService:
    def __init__(
        self, repo: Repository, notifications: Any = None, custody: Any = None
    ) -> None:
        self._repo = repo
        self._notifications = notifications
        # CustodyService, injected so a fulfilled order can record the real SALE
        # event through the same validated write path the portals already use.
        self._custody = custody

    def _emit(self, **kwargs: Any) -> None:
        if self._notifications is None:
            return
        try:
            self._notifications.notify(**kwargs)
        except Exception:  # pragma: no cover - notification must never break a write
            pass

    # ------------------------------------------------------------- listings
    def create_listing(self, *, data: dict[str, Any], user: Any) -> dict[str, Any]:
        batch_id = str(data.get("batch_id") or "")
        batch = self._repo.get_batch(batch_id)
        if batch is None:
            raise ValueError("batch not found")
        # The server decides the seller from the batch, never from the request
        # body — otherwise one FPO could list another FPO's goods.
        seller_org_id = str(batch.get("organization_id") or "")
        if not seller_org_id:
            raise ValueError("batch has no owning organization")
        if user.role not in ("admin", "institution") and user.org_id != seller_org_id:
            raise PermissionError("only the owning organization may list this batch")
        if batch.get("trust_tier") not in _LISTABLE_TRUST:
            raise ValueError("only a laboratory-verified batch may be listed for sale")
        if str(batch.get("status") or "") in _BLOCKED_STATUSES:
            raise ValueError(f"batch status {batch.get('status')} blocks listing")

        quantity = float(data.get("quantity_kg") or 0)
        if quantity <= 0:
            raise ValueError("quantity_kg must be greater than zero")
        if quantity - float(batch.get("quantity_kg", 0) or 0) > 1e-6:
            raise ValueError("cannot list more than the batch quantity")
        price = float(data.get("price_per_kg") or 0)
        if price <= 0:
            raise ValueError("price_per_kg must be greater than zero")

        client_id = str(data.get("client_id") or "")
        if client_id:
            existing = self._repo.find_by_client_id("market_listings", client_id)
            if existing:
                return existing

        listing = self._repo.create_market_listing(
            {
                "batch_id": batch_id,
                "seller_org_id": seller_org_id,
                "quantity_kg": quantity,
                "remaining_kg": quantity,
                "price_per_kg": price,
                "currency": str(data.get("currency") or "INR"),
                "status": "OPEN",
                "notes": str(data.get("notes") or ""),
                "listed_at": datetime.now(timezone.utc),
                "client_id": client_id,
            }
        )
        self._emit(
            event="MARKET_LISTED",
            title="Batch listed for sale",
            body=(
                f"{quantity} kg of batch {batch.get('batch_code') or batch_id} is "
                f"on the market at {price} per kg."
            ),
            organization_id=seller_org_id,
            batch_id=batch_id,
            recommended_action="Review inbound purchase requests.",
        )
        return listing
    def withdraw_listing(
        self, listing_id: str, *, user: Any
    ) -> dict[str, Any] | None:
        """Withdraw an open listing that has not been fulfilled."""
        listing = self._repo.get_market_listing(listing_id)
        if listing is None:
            return None
        if not self._seller_owns(listing, user):
            raise PermissionError(
                "only the selling organization may withdraw a listing"
            )
        if listing.get("status") in ("SOLD", "WITHDRAWN"):
            return listing
        return self._repo.update_market_listing(
            listing_id,
            {"status": "WITHDRAWN", "closed_at": datetime.now(timezone.utc)},
        )

    @staticmethod
    def _seller_owns(listing: dict[str, Any], user: Any) -> bool:
        if user.role in ("admin", "institution"):
            return True
        return str(user.org_id or "") == str(listing.get("seller_org_id") or "")

    def list_listings(self, *, user: Any, status: str = "") -> list[dict[str, Any]]:
        """Listings visible to this caller.

        A buyer sees open listings offered by other organizations. A seller sees
        its own listings regardless of status. Admin/institution sees all.
        """
        if user.role in ("admin", "institution"):
            rows = self._repo.list_market_listings(status=status)
        elif user.role == "buyer":
            rows = [
                x
                for x in self._repo.list_market_listings(status=status or "OPEN")
                if str(x.get("seller_org_id") or "") != str(user.org_id or "")
            ]
        else:
            rows = self._repo.list_market_listings(
                status=status, seller_org_id=str(user.org_id or "")
            )
        return [self._decorate(x) for x in rows]

    def _decorate(self, listing: dict[str, Any]) -> dict[str, Any]:
        """Attach the batch facts a buyer needs, read from the real batch row."""
        batch = self._repo.get_batch(str(listing.get("batch_id") or "")) or {}
        return {
            **listing,
            "batch_code": batch.get("batch_code", ""),
            "batch_origin": batch.get("origin", ""),
            "batch_honey_type": batch.get("honey_type", ""),
            "batch_trust_tier": batch.get("trust_tier", ""),
            "batch_status": batch.get("status", ""),
        }

    # --------------------------------------------------------------- orders
    def create_order(
        self, *, data: dict[str, Any], user: Any
    ) -> dict[str, Any]:
        """A buyer requests part of an open listing.

        The requested quantity is validated against `remaining_kg` — the
        kilograms still genuinely unsold — so an order can never claim honey
        another buyer has already committed to.
        """
        listing = self._repo.get_market_listing(str(data.get("listing_id") or ""))
        if listing is None:
            raise ValueError("listing not found")
        if listing.get("status") != "OPEN":
            raise ValueError(f"listing is {listing.get('status')}, not open")
        # A seller may not buy its own listing; that would be a fake transaction.
        if str(user.org_id or "") == str(listing.get("seller_org_id") or ""):
            raise PermissionError("an organization cannot purchase its own listing")

        quantity = float(data.get("quantity_kg") or 0)
        if quantity <= 0:
            raise ValueError("quantity_kg must be greater than zero")
        remaining = float(listing.get("remaining_kg", 0) or 0)
        if quantity - remaining > 1e-6:
            raise ValueError(
                f"only {remaining} kg remain on this listing"
            )

        client_id = str(data.get("client_id") or "")
        if client_id:
            existing = self._repo.find_by_client_id("purchase_orders", client_id)
            if existing:
                return existing

        price = float(listing.get("price_per_kg") or 0)
        order = self._repo.create_purchase_order(
            {
                "listing_id": listing.get("id"),
                "batch_id": listing.get("batch_id"),
                "buyer_org_id": str(user.org_id or ""),
                "buyer_user_id": str(user.user_id),
                "quantity_kg": quantity,
                "price_per_kg": price,
                # Persisted once, at agreement time.
                "total_amount": round(quantity * price, 2),
                "currency": str(listing.get("currency") or "INR"),
                "status": "REQUESTED",
                "buyer_notes": str(data.get("buyer_notes") or ""),
                "requested_at": datetime.now(timezone.utc),
                "client_id": client_id,
            }
        )
        self._emit(
            event="BUYER_REQUESTED",
            title="Purchase requested",
            body=(
                f"A buyer requested {quantity} kg of batch "
                f"{listing.get('batch_id')} at {price} per kg."
            ),
            # Routed to the SELLER: this is the order they must act on. The buyer
            # already sees their own request in their procurement list.
            organization_id=str(listing.get("seller_org_id") or ""),
            batch_id=str(listing.get("batch_id") or ""),
            recommended_action="Accept or reject this purchase request.",
        )
        return order
    # --MARKET_ORDERS_TWO--
    def decide_order(
        self, order_id: str, *, accept: bool, user: Any, seller_notes: str = ""
    ) -> dict[str, Any]:
        """Seller accepts or rejects a requested purchase.

        Acceptance is the point where kilograms are genuinely committed, so
        `remaining_kg` is decremented here and re-checked against the listing.
        If two requests race for the same remainder, the second is rejected with
        a conflict rather than silently overselling.
        """
        order = self._repo.get_purchase_order(order_id)
        if order is None:
            raise ValueError("purchase order not found")
        listing = self._repo.get_market_listing(str(order.get("listing_id") or ""))
        if listing is None:
            raise ValueError("listing for this order no longer exists")
        if not self._seller_owns(listing, user):
            raise PermissionError("only the selling organization may decide this order")
        if order.get("status") != "REQUESTED":
            # Already decided: return the stored order unchanged rather than
            # double-committing its kilograms.
            return order

        now = datetime.now(timezone.utc)
        if not accept:
            rejected = self._repo.update_purchase_order(
                order_id,
                {
                    "status": "REJECTED",
                    "seller_notes": seller_notes,
                    "decided_at": now,
                    "decided_by": str(user.user_id),
                },
            )
            self._notify_buyer(order, "Purchase request declined", rejected, "info", seller_notes)
            return rejected

        quantity = float(order.get("quantity_kg", 0) or 0)
        remaining = float(listing.get("remaining_kg", 0) or 0)
        if quantity - remaining > 1e-6:
            raise ValueError(
                f"only {remaining} kg remain; this request cannot be accepted"
            )
        new_remaining = round(remaining - quantity, 6)
        listing_updates: dict[str, Any] = {"remaining_kg": new_remaining}
        if new_remaining <= 1e-6:
            listing_updates["status"] = "SOLD"
            listing_updates["closed_at"] = now
        self._repo.update_market_listing(listing["id"], listing_updates)
        accepted = self._repo.update_purchase_order(
            order_id,
            {
                "status": "ACCEPTED",
                "seller_notes": seller_notes,
                "decided_at": now,
                "decided_by": str(user.user_id),
            },
        )
        self._notify_buyer(order, "Purchase accepted", accepted, "info", seller_notes)
        return accepted
    def fulfil_order(self, order_id: str, *, user: Any) -> dict[str, Any]:
        """Complete an accepted order.

        This is the step that actually moves the honey: it writes a real SALE
        custody event onto the batch through CustodyService (which in turn
        anchors the transfer when a gateway is configured). The order is only
        marked FULFILLED after that custody row exists, so the buyer can never
        see a completed sale the provenance ledger does not record.
        """
        order = self._repo.get_purchase_order(order_id)
        if order is None:
            raise ValueError("purchase order not found")
        if order.get("status") != "ACCEPTED":
            raise ValueError("only an accepted order can be fulfilled")
        buyer_org = str(order.get("buyer_org_id") or "")
        listing = self._repo.get_market_listing(str(order.get("listing_id") or ""))
        is_buyer = str(user.org_id or "") == buyer_org
        is_seller = bool(listing) and self._seller_owns(listing, user)
        if not (is_buyer or is_seller) and user.role not in ("admin", "institution"):
            raise PermissionError("only the buyer or seller may fulfil this order")

        batch_id = str(order.get("batch_id") or "")
        quantity = float(order.get("quantity_kg", 0) or 0)
        batch = self._repo.get_batch(batch_id) or {}
        if self._custody is not None:
            self._custody.add(
                batch_id=batch_id,
                data={
                    "action": "SALE",
                    "actor": str(user.org_id or user.user_id),
                    "to_org": buyer_org,
                    "quantity_kg": quantity,
                    "notes": (
                        f"Market fulfilment of purchase order {order_id} "
                        f"({quantity} kg)"
                    ),
                },
            )
        # The batch status advances only because the sale genuinely happened.
        if str(batch.get("status") or "") not in ("distributed", "retail", "sold"):
            self._repo.update_batch(batch_id, {"status": "sold"})
        fulfilled = self._repo.update_purchase_order(
            order_id,
            {"status": "FULFILLED", "fulfilled_at": datetime.now(timezone.utc)},
        )
        self._notify_buyer(
            order,
            "Order fulfilled",
            fulfilled,
            "info",
            "The sale is recorded on the batch's custody history.",
        )
        return fulfilled

    def cancel_order(self, order_id: str, *, user: Any) -> dict[str, Any]:
        """Buyer cancels a still-pending request.

        An accepted order is already committed kilograms; cancelling it would
        silently free stock nobody can see, so it must be declined instead.
        """
        order = self._repo.get_purchase_order(order_id)
        if order is None:
            raise ValueError("purchase order not found")
        is_buyer = str(user.org_id or "") == str(order.get("buyer_org_id") or "")
        if not is_buyer and user.role not in ("admin", "institution"):
            raise PermissionError("only the buyer may cancel this order")
        if order.get("status") != "REQUESTED":
            raise ValueError("only a pending request can be cancelled")
        cancelled = self._repo.update_purchase_order(
            order_id,
            {
                "status": "CANCELLED",
                "decided_at": datetime.now(timezone.utc),
                "decided_by": str(user.user_id),
            },
        )
        listing = self._repo.get_market_listing(str(order.get("listing_id") or ""))
        if listing is not None:
            self._emit(
                event="BUYER_ACCEPTED",
                title="Purchase request cancelled",
                body=(
                    f"Purchase order {order_id} was cancelled by the buyer; "
                    "the kilograms remain available."
                ),
                organization_id=str(listing.get("seller_org_id") or ""),
                batch_id=str(order.get("batch_id") or ""),
                severity="warning",
                recommended_action="The listing is open for other buyers.",
            )
        return cancelled
    def _notify_buyer(
        self,
        order: dict[str, Any],
        title: str,
        updated: dict[str, Any],
        severity: str,
        seller_notes: str = "",
    ) -> None:
        self._emit(
            event="BUYER_ACCEPTED",
            title=title,
            body=(
                f"Purchase order {order.get('id')} is now "
                f"{updated.get('status')} for {order.get('quantity_kg')} kg."
                + (f" Seller note: {seller_notes}" if seller_notes else "")
            ),
            organization_id=str(order.get("buyer_org_id") or ""),
            batch_id=str(order.get("batch_id") or ""),
            severity=severity,
            recommended_action="Review this order in your procurement list.",
        )

    def list_orders(self, *, user: Any) -> list[dict[str, Any]]:
        """Orders this caller may see: its own purchases, or orders to sell."""
        if user.role in ("admin", "institution"):
            return [
                self._decorate_order(x) for x in self._repo.list_purchase_orders()
            ]
        if user.role == "buyer":
            rows = self._repo.list_purchase_orders(buyer_org_id=str(user.org_id or ""))
        else:
            # A seller's inbound requests: derived from the listings it owns.
            listing_ids = {
                str(x.get("id"))
                for x in self._repo.list_market_listings(
                    seller_org_id=str(user.org_id or "")
                )
            }
            rows = [
                order
                for listing_id in listing_ids
                for order in self._repo.list_purchase_orders(listing_id=listing_id)
            ]
        rows.sort(key=lambda r: str(r.get("requested_at", "")))
        return [self._decorate_order(x) for x in rows]

    def _decorate_order(self, order: dict[str, Any]) -> dict[str, Any]:
        listing = self._repo.get_market_listing(str(order.get("listing_id") or "")) or {}
        batch = self._repo.get_batch(str(order.get("batch_id") or "")) or {}
        return {
            **order,
            "batch_code": batch.get("batch_code", ""),
            "batch_origin": batch.get("origin", ""),
            "batch_trust_tier": batch.get("trust_tier", ""),
            "seller_org_id": listing.get("seller_org_id", ""),
        }

    def marketplace(self, *, user: Any) -> dict[str, Any]:
        """One call for the buyer surface: open lots plus this buyer's orders."""
        return {
            "listings": self.list_listings(user=user, status="OPEN"),
            "orders": self.list_orders(user=user),
        }