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
    def __init__(self, repo: Repository) -> None:
        self._repo = repo

    # ------------------------------------------------------------------ create
    def create(self, *, data: dict[str, Any]) -> dict[str, Any]:
        client_id = data.get("client_id") or ""
        if client_id:
            existing = self._repo.find_by_client_id("batches", client_id)
            if existing:
                return existing
        batch = {
            "batch_code": data["batch_code"],
            "organization_id": data.get("organization_id", ""),
            "origin": data.get("origin", ""),
            "honey_type": data.get("honey_type", "Not specified"),
            "quantity_kg": data["quantity_kg"],
            "status": data.get("status") or "created",
            "trust_tier": "self_declared",
            "created_at": data.get("created_at") or datetime.now(timezone.utc),
        }
        created = self._repo.create_batch(batch, client_id=client_id)
        for harvest_id in data.get("harvest_ids", []):
            self._repo.link_batch_harvest(
                created["id"], harvest_id, data["quantity_kg"]
            )
        return created

    # ------------------------------------------------------------------ read
    def get_for_user(self, batch_id: str, *, user: Any) -> dict[str, Any] | None:
        batch = self._repo.get_batch(batch_id)
        if batch is None:
            return None
        if user.role in ("admin", "lab", "processor", "institution", "buyer"):
            return batch
        if user.role == "beekeeper":
            harvest_ids = {
                link.get("harvest_id")
                for link in self._repo.list_batch_harvests(batch_id)
            }
            mine = {
                h.get("id")
                for h in self._repo.list_harvests(user.user_id)
                if h.get("id") in harvest_ids
            }
            if mine:
                return batch
            return None
        # FPO / org users
        if batch.get("organization_id") == user.org_id:
            return batch
        return None

    def get_for_code(self, code: str) -> dict[str, Any] | None:
        return self._repo.get_batch_by_code(code)

    def list_for_user(self, *, user: Any) -> list[dict[str, Any]]:
        if user.role in ("admin", "institution", "lab", "processor", "buyer"):
            return self._repo.list_batches("")
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

    # ------------------------------------------------------------------ split
    def split(
        self, parent_id: str, child_quantities_kg: list[float], origin_hint: str = ""
    ) -> dict[str, Any]:
        parent = self._repo.get_batch(parent_id)
        if parent is None:
            return {"error": "parent batch not found"}
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
            children.append(child)
        return {"parent": parent, "children": children}

    # ------------------------------------------------------------------ merge
    def merge(
        self, batch_ids: list[str], new_batch_code: str
    ) -> dict[str, Any]:
        sources = []
        harvest_ids: list[str] = []
        for batch_id in sorted(set(batch_ids)):
            source = self._repo.get_batch(batch_id)
            if source is None:
                return {"error": f"source batch not found: {batch_id}"}
            sources.append(source)
            harvest_ids.extend(
                link.get("harvest_id")
                for link in self._repo.list_batch_harvests(batch_id)
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
        for harvest_id in dict.fromkeys(harvest_ids):
            self._repo.link_batch_harvest(merged["id"], harvest_id, total_kg)
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