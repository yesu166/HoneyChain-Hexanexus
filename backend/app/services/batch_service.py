from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository

_TRUST_RANK = {
    "self_declared": 0,
    "organization_verified": 1,
    "lab_verified": 2,
    "blockchain_anchored": 3,
}

_TYPE_BY_RANK = [
    "self_declared",
    "organization_verified",
    "lab_verified",
    "blockchain_anchored",
]

# Explicit, event-based route labels. A batch may move through any path; no
# single supply chain is hardcoded.
VALID_CUSTODY_ACTIONS = (
    "HARVEST",
    "COLLECTION",
    "QUALITY_TEST",
    "PROCESSING",
    "PACKAGING",
    "TRANSFER",
    "DISTRIBUTION",
    "SALE",
    "CORRECTION",
)


def weakest_tier(tiers: list[str]) -> str:
    """Merged lots may never exceed their weakest contributing evidence."""
    if not tiers:
        return "self_declared"
    ranks = [_TRUST_RANK.get(t, 0) for t in tiers]
    return _TYPE_BY_RANK[min(ranks)]


class BatchService:
    def __init__(self, repo: Repository, gateway: Any = None) -> None:
        self._repo = repo
        # BlockchainGateway facade; optional for tests. When present, every
        # real parent->child genealogy relation (split/merge) is anchored.
        self._gateway = gateway

    def _anchor_lineage(
        self, *, input_batch_id: str, output_batch_id: str,
        operation: str, quantity_kg: float,
    ) -> dict[str, Any] | None:
        if self._gateway is None:
            return None
        try:
            return self._gateway.submit_lineage_event(
                input_batch_id=input_batch_id,
                output_batch_id=output_batch_id,
                operation=operation,
                quantity_kg=float(quantity_kg or 0),
            )
        except Exception as exc:  # pragma: no cover - defensive
            return {"state": "UNKNOWN", "error": str(exc)}

    # ------------------------------------------------------------------ create
    def create(self, *, data: dict[str, Any], user: Any = None) -> dict[str, Any]:
        client_id = data.get("client_id") or ""
        if client_id:
            existing = self._repo.find_by_client_id("batches", client_id)
            if existing:
                return existing
        # The server decides the owning organization. Org-bound roles can never
        # write into another FPO's org, even if the client sends an org_id.
        org_id = data.get("organization_id", "")
        if user is not None and user.role in ("fpo", "processor", "beekeeper"):
            org_id = user.org_id
        elif user is not None and not org_id:
            org_id = user.org_id or ""

        # Mass balance with explicit per-harvest allocation. A batch consumes its
        # quantity from the linked harvests: with one harvest the whole batch
        # quantity is assigned to it; with several harvests the caller must
        # supply harvest_allocations that sum exactly to the batch quantity and
        # do not exceed any harvest's remaining quantity. Remaining quantity is
        # the harvest total minus allocations already consumed by other batches
        # (split children keep their own rows, so they never re-consume the
        # harvest; merged sources are excluded because they no longer exist as
        # sellable lots). Without this gate a 50 kg batch linked to two 30 kg
        # harvests could silently claim 50 kg against EACH harvest.
        harvest_ids = list(data.get("harvest_ids", []) or [])
        raw_allocations = data.get("harvest_allocations") or []
        allocations: list[tuple[str, float]] = []
        for entry in raw_allocations:
            if isinstance(entry, dict):
                allocations.append(
                    (str(entry.get("harvest_id") or ""), float(entry.get("quantity_kg", 0) or 0))
                )
            else:
                allocations.append(
                    (str(getattr(entry, "harvest_id", "") or ""), float(getattr(entry, "quantity_kg", 0) or 0))
                )
        if allocations:
            allocation_ids = [harvest_id for harvest_id, _ in allocations]
            if sorted(allocation_ids) != sorted(harvest_ids):
                return {"error": "harvest_allocations must cover exactly harvest_ids"}
            if any(quantity <= 0 for _, quantity in allocations):
                return {"error": "harvest_allocations quantities must be positive"}
            if abs(sum(quantity for _, quantity in allocations) - float(data["quantity_kg"])) > 1e-6:
                return {
                    "error": (
                        "harvest_allocations must sum to the batch "
                        f"quantity ({data['quantity_kg']} kg)"
                    )
                }
            for harvest_id, quantity in allocations:
                harvest = self._repo.get_harvest(harvest_id)
                if harvest is None:
                    return {"error": f"linked harvest not found: {harvest_id}"}
                remaining = self._remaining_harvest_quantity(harvest_id)
                if quantity - remaining > 1e-6:
                    return {
                        "error": (
                            f"allocation ({quantity} kg) exceeds remaining "
                            f"harvest quantity ({remaining} kg) for {harvest_id}"
                        )
                    }
        elif harvest_ids:
            if len(harvest_ids) > 1:
                return {
                    "error": (
                        "multi-harvest batches require explicit harvest_allocations "
                        "so each kilogram is counted once"
                    )
                }
            harvest = self._repo.get_harvest(harvest_ids[0])
            if harvest is None:
                return {"error": f"linked harvest not found: {harvest_ids[0]}"}
            requested = float(data["quantity_kg"])
            remaining = self._remaining_harvest_quantity(harvest_ids[0])
            if requested - remaining > 1e-6:
                return {
                    "error": (
                        f"batch quantity ({requested} kg) exceeds remaining "
                        f"harvest quantity ({remaining} kg)"
                    )
                }
            allocations = [(harvest_ids[0], requested)]

        batch = {
            "batch_code": data["batch_code"],
            "organization_id": org_id,
            "origin": data.get("origin", ""),
            "honey_type": data.get("honey_type", "Not specified"),
            "quantity_kg": data["quantity_kg"],
            "status": data.get("status") or "created",
            "trust_tier": "self_declared",
            "created_at": data.get("created_at") or datetime.now(timezone.utc),
        }
        created = self._repo.create_batch(batch, client_id=client_id)
        for harvest_id, allocated in allocations:
            self._repo.link_batch_harvest(created["id"], harvest_id, allocated)
        return created

    # ------------------------------------------------------------------ read
    def in_user_scope(self, batch: dict[str, Any], *, user: Any) -> bool:
        """Boolean scope check matching [get_for_user] without 404 semantics.

        Beyond org ownership, an actor that RECEIVED custody of the batch (a
        TRANSFER custody event naming it via to_actor/to_org) is in scope: the
        physical holder of the goods must be able to assert facts about them,
        without rewriting the batch's owning organization.
        """
        if user.role in ("admin", "institution", "lab", "buyer"):
            return True
        if user.role == "processor" and batch.get("organization_id") == user.org_id:
            return True
        if user.role != "beekeeper":
            to_actor = str(getattr(user, "user_id", "") or "")
            to_org = str(getattr(user, "org_id", "") or "")
            if to_actor or to_org:
                for event in self._repo.list_custody_events(batch.get("id", "")):
                    if to_actor and event.get("to_actor") == to_actor:
                        return True
                    if to_org and event.get("to_org") == to_org:
                        return True
        if user.role == "beekeeper":
            harvest_ids = {
                link.get("harvest_id")
                for link in self._repo.list_batch_harvests(batch.get("id", ""))
            }
            mine = {
                h.get("id")
                for h in self._repo.list_harvests(user.user_id)
                if h.get("id") in harvest_ids
            }
            return bool(mine)
        # FPO / org users
        return batch.get("organization_id") == user.org_id

    def get_for_user(self, batch_id: str, *, user: Any) -> dict[str, Any] | None:
        batch = self._repo.get_batch(batch_id)
        if batch is None:
            return None
        if self.in_user_scope(batch, user=user):
            return batch
        return None

    def get_for_code(self, code: str) -> dict[str, Any] | None:
        return self._repo.get_batch_by_code(code)

    def list_for_user(self, *, user: Any) -> list[dict[str, Any]]:
        if user.role in ("admin", "institution", "lab", "buyer"):
            return self._repo.list_batches("")
        if user.role == "processor":
            return self._repo.list_batches(user.org_id)
        if user.role == "beekeeper":
            batch_ids = set()
            for harvest in self._repo.list_harvests(user.user_id):
                for link in self._repo.list_batch_harvests_by_harvest(
                    harvest.get("id")
                ):
                    batch_ids.add(link.get("batch_id"))
            rows = []
            for batch_id in batch_ids:
                batch = self._repo.get_batch(batch_id)
                if batch:
                    rows.append(batch)
            return rows
        return self._repo.list_batches(user.org_id)

    def list_harvest_ids(self, batch_id: str) -> list[str]:
        return [
            link.get("harvest_id")
            for link in self._repo.list_batch_harvests(batch_id)
        ]

    def _remaining_harvest_quantity(
        self, harvest_id: str, *, exclude_ids: set[str] | None = None
    ) -> float:
        """Harvest total minus quantities already allocated to live batches.

        A batch is "live" while it still holds harvest material: superseded
        parents (split children or merged lots) are excluded, because their
        allocation lives on in their children and would otherwise be counted
        twice. [exclude_ids] omits specific batches from the consumed sum.
        """
        harvest = self._repo.get_harvest(harvest_id)
        if harvest is None:
            return 0.0
        total = float(harvest.get("quantity_kg", 0) or 0)
        excluded = exclude_ids or set()
        consumed = 0.0
        for link in self._repo.list_batch_harvests_by_harvest(harvest_id):
            batch_id = str(link.get("batch_id") or "")
            if not batch_id or batch_id in excluded:
                continue
            if self._batch_is_superseded(batch_id):
                continue
            consumed += float(link.get("quantity_kg", 0) or 0)
        return max(total - consumed, 0.0)

    def _batch_is_superseded(self, batch_id: str) -> bool:
        """True when the batch has split children or a merged successor.

        Such batches no longer exist as independently sellable lots: their
        material (and their harvest allocation) carries into the children, so
        their own allocation must not also count against the harvest.
        """
        if not batch_id:
            return False
        for rel in self._repo.list_batch_relations(batch_id, direction="children"):
            if str(rel.get("child_batch_id") or ""):
                return True
        return False

    def _propagate_harvest_quantity(
        self, *, source_batch_id: str, target_batch_id: str, target_quantity: float
    ) -> None:
        """Carry a source batch's harvest links onto a split child.

        The child receives a proportional slice of each harvest the parent
        consumed, so lineage preserves WHERE the material came from without
        re-claiming quantity against the harvest.
        """
        links = self._repo.list_batch_harvests(source_batch_id)
        if not links:
            return
        parent_qty = float(
            self._repo.get_batch(source_batch_id).get("quantity_kg", 0) or 0
        )
        if parent_qty <= 0:
            return
        share = min(target_quantity / parent_qty, 1.0)
        for link in links:
            allocated = float(link.get("quantity_kg", 0) or 0) * share
            self._repo.link_batch_harvest(target_batch_id, link.get("harvest_id"), allocated)

    # ------------------------------------------------------------------ split
    def split(
        self, parent_id: str, child_quantities_kg: list[float], origin_hint: str = "",
        *, user: Any = None,
    ) -> dict[str, Any]:
        parent = self._repo.get_batch(parent_id)
        if parent is None:
            return {"error": "parent batch not found"}
        if user is not None and not self.in_user_scope(parent, user=user):
            return {"error": "batch not in your scope"}
        total = sum(child_quantities_kg)
        if abs(total - float(parent.get("quantity_kg", 0))) > 1e-6:
            return {
                "error": (
                    f"child quantities ({total}) must sum to the parent "
                    f"quantity ({parent.get('quantity_kg')})"
                )
            }
        children = []
        for index, qty in enumerate(child_quantities_kg, start=1):
            child = self._repo.create_batch(
                {
                    "batch_code": f"{parent.get('batch_code')}-{chr(64 + index)}",
                    "organization_id": parent.get("organization_id", ""),
                    "origin": origin_hint or parent.get("origin", ""),
                    "honey_type": parent.get("honey_type", "Not specified"),
                    "quantity_kg": qty,
                    "status": "created",
                    "trust_tier": parent.get("trust_tier", "self_declared"),
                    "created_at": datetime.now(timezone.utc),
                }
            )
            self._repo.add_batch_relation(
                {
                    "parent_batch_id": parent_id,
                    "child_batch_id": child["id"],
                    "relation_type": "SPLIT_FROM",
                    "quantity_kg": qty,
                }
            )
            # Anchor the real parent->child relation after it is persisted.
            self._anchor_lineage(
                input_batch_id=parent_id,
                output_batch_id=child["id"],
                operation="SPLIT_FROM",
                quantity_kg=qty,
            )
            self._propagate_harvest_quantity(
                source_batch_id=parent_id,
                target_batch_id=child["id"],
                target_quantity=qty,
            )
            children.append(child)
        return {"parent": parent, "children": children}

    # ------------------------------------------------------------------ merge
    def merge(
        self, batch_ids: list[str], new_batch_code: str,
        *, user: Any = None,
    ) -> dict[str, Any]:
        sources = []
        # harvest_id -> quantity contributed to the merged batch, summed across
        # sources so two lots drawing on the same harvest add up correctly.
        _harvest_qty: dict[str, float] = {}
        for batch_id in sorted(set(batch_ids)):
            source = self._repo.get_batch(batch_id)
            if source is None:
                return {"error": f"source batch not found: {batch_id}"}
            if user is not None and not self.in_user_scope(source, user=user):
                return {"error": f"source batch not in your scope: {batch_id}"}
            sources.append(source)
            for link in self._repo.list_batch_harvests(batch_id):
                harvest_id = str(link.get("harvest_id") or "")
                if harvest_id:
                    _harvest_qty[harvest_id] = _harvest_qty.get(harvest_id, 0.0) + float(
                        link.get("quantity_kg", 0) or 0
                    )
        total_kg = sum(float(s.get("quantity_kg", 0)) for s in sources)
        merged_tier = weakest_tier(
            [str(s.get("trust_tier", "self_declared")) for s in sources]
        )
        org_id = next(
            (s.get("organization_id") for s in sources if s.get("organization_id")),
            "",
        )
        merged = self._repo.create_batch(
            {
                "batch_code": new_batch_code,
                "organization_id": org_id,
                "origin": "Mixed" if len(sources) > 1 else sources[0].get("origin", ""),
                "honey_type": "Multifloral" if len(sources) > 1 else sources[0].get("honey_type", ""),
                "quantity_kg": total_kg,
                "status": "created",
                "trust_tier": merged_tier,
                "created_at": datetime.now(timezone.utc),
            }
        )
        for source in sources:
            self._repo.add_batch_relation(
                {
                    "parent_batch_id": source["id"],
                    "child_batch_id": merged["id"],
                    "relation_type": "AGGREGATED_FROM",
                    "quantity_kg": source.get("quantity_kg"),
                }
            )
            # Anchor each real source->merged relation after it is persisted.
            self._anchor_lineage(
                input_batch_id=source["id"],
                output_batch_id=merged["id"],
                operation="AGGREGATED_FROM",
                quantity_kg=float(source.get("quantity_kg") or 0),
            )
        # Mass conservation: the merged batch consumes exactly what its sources
        # consumed. Link each harvest with the quantity that came from it —
        # never the full merged total per harvest, which would double-count a
        # kilogram against every contributing harvest at once.
        for harvest_id, qty in sorted(_harvest_qty.items()):
            self._repo.link_batch_harvest(merged["id"], harvest_id, qty)
        return {"merged": merged, "sources": sources}

    def genealogy(self, batch_id: str) -> list[dict[str, Any]]:
        """Breadth-first walk of the explicit relation graph."""
        visited: set[str] = set()
        frontier = [batch_id]
        tree: list[dict[str, Any]] = []
        while frontier:
            current = frontier.pop(0)
            if current in visited:
                continue
            visited.add(current)
            batch = self._repo.get_batch(current)
            if batch is None:
                continue
            relations = self._repo.list_batch_relations(current)
            tree.append(
                {
                    "id": batch["id"],
                    "batch_code": batch.get("batch_code"),
                    "quantity_kg": batch.get("quantity_kg"),
                    "trust_tier": batch.get("trust_tier"),
                    "relations": [
                        {
                            "type": rel.get("relation_type"),
                            "other": rel.get("child_batch_id")
                            if rel.get("parent_batch_id") == current
                            else rel.get("parent_batch_id"),
                        }
                        for rel in relations
                    ],
                }
            )
            for rel in relations:
                other = (
                    rel.get("child_batch_id")
                    if rel.get("parent_batch_id") == current
                    else rel.get("parent_batch_id")
                )
                if other and other not in visited:
                    frontier.append(other)
        return tree

    def genealogy_codes(self, batch_id: str) -> list[str]:
        return [
            node.get("batch_code", "")
            for node in self.genealogy(batch_id)
            if node.get("batch_code")
        ]

    def set_trust(self, batch_id: str, tier: str) -> dict[str, Any] | None:
        return self._repo.update_batch(batch_id, {"trust_tier": tier})