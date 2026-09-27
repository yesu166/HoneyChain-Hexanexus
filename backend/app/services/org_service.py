"""Org-scoped aggregate metrics for FPO dashboards.

Every number here is derived server-side from the repository (real backend
state), never invented by a client. Counters start at their true value — an FPO
with no beekeepers yet reads 0, not a demo estimate.
"""
from __future__ import annotations

from typing import Any

from ..db.supabase import Repository

_PENDING_BATCH_STATUSES = ("created", "collected", "pending", "lab_pending")
_VERIFIED_TIERS = ("lab_verified", "blockchain_anchored")


class OrgService:
    def __init__(self, repo: Repository) -> None:
        self._repo = repo

    def dashboard(self, org_id: str, *, response_org_id: str | None = None) -> dict[str, Any]:
        # Repository FK columns use the organization UUID, while users and
        # invites may carry the public ORG-xxxxxx key. Normalize once at the
        # service boundary so all dashboard aggregates query the same tenant.
        org = self._repo.get_organization(org_id)
        if org is None:
            for candidate in self._repo.list_organizations():
                if str(candidate.get("organization_key") or "") == str(org_id):
                    org = candidate
                    break
        org = org or {}
        canonical_org_id = str(org.get("id") or org_id)

        beekeepers = self._repo.list_beekeepers(canonical_org_id)
        beekeeper_ids = {b["id"] for b in beekeepers}

        batches = self._repo.list_batches(canonical_org_id)
        batch_ids = {b["id"] for b in batches}

        # Harvests owned by the org's beekeepers, plus harvests linked into the
        # org's batches (an FPO-recorded harvest is counted through its batch).
        harvest_rows = self._repo.list_harvests(None, org_id=canonical_org_id)
        harvest_by_id: dict[str, dict[str, Any]] = {
            h.get("id"): h for h in harvest_rows if h.get("id")
        }
        for batch in batches:
            for link in self._repo.list_batch_harvests(batch.get("id", "")):
                hid = link.get("harvest_id")
                if hid and hid not in harvest_by_id:
                    harvest = self._repo.get_harvest(hid)
                    if harvest is not None:
                        harvest_by_id[hid] = harvest

        hives = [
            h for h in self._repo.list_hives(None)
            if h.get("beekeeper_id") in beekeeper_ids
        ]

        collections = 0
        recent: list[dict[str, Any]] = []
        for batch in batches:
            for event in self._repo.list_custody_events(batch.get("id", "")):
                if event.get("action") == "COLLECTION":
                    collections += 1
                recent.append(
                    {
                        "type": "custody",
                        "label": f"{event.get('action')} · {batch.get('batch_code')}",
                        "timestamp": str(event.get("event_at") or ""),
                        "entity_ref": batch.get("id", ""),
                    }
                )

        for harvest in harvest_by_id.values():
            recent.append(
                {
                    "type": "harvest",
                    "label": f"{round(float(harvest.get('quantity_kg', 0)), 1)} kg "
                    f"{harvest.get('honey_type', 'honey')} harvested",
                    "timestamp": str(harvest.get("harvested_at") or ""),
                    "entity_ref": harvest.get("id", ""),
                }
            )
        for batch in batches:
            recent.append(
                {
                    "type": "batch",
                    "label": f"Batch {batch.get('batch_code')} → {batch.get('status')}",
                    "timestamp": str(batch.get("created_at") or ""),
                    "entity_ref": batch.get("id", ""),
                }
            )

        recent.sort(key=lambda r: str(r["timestamp"]), reverse=True)
        recent_activity = recent[:10]

        verified = [
            b for b in batches
            if str(b.get("trust_tier")) in _VERIFIED_TIERS
        ]
        pending = [
            b for b in batches
            if str(b.get("status")) in _PENDING_BATCH_STATUSES
        ]
        clusters = len(
            {
                o.get("cluster_id")
                for o in self._repo.list_organizations()
                if o.get("id") == org_id and o.get("cluster_id")
            }
        )

        return {
            "org_id": response_org_id or org_id,
            "org_name": org.get("name", ""),
            "active_beekeepers": len(beekeepers),
            "hives": len(hives),
            "clusters": clusters,
            "honey_harvested_kg": round(
                sum(float(h.get("quantity_kg", 0)) for h in harvest_by_id.values()), 2
            ),
            "collections": collections,
            "batches": len(batches),
            "verified_batches": len(verified),
            "pending_actions": len(pending),
            "recent_activity": recent_activity,
            "source": "backend",
        }

    def platform_stats(self) -> dict[str, Any]:
        batches = self._repo.list_batches("")
        batch_ids = [b.get("id", "") for b in batches if b.get("id")]

        # Bulk fetch lab tests and certificates for all batches at once
        lab_tests_by_batch: dict[str, list[dict]] = {}
        certificates_by_batch: dict[str, list[dict]] = {}
        if batch_ids:
            lab_tests = self._repo.list_lab_tests_for_batches(batch_ids)
            certificates = self._repo.list_certificates_for_batches(batch_ids)
            for test in lab_tests:
                lab_tests_by_batch.setdefault(test.get("batch_id", ""), []).append(test)
            for cert in certificates:
                certificates_by_batch.setdefault(cert.get("batch_id", ""), []).append(cert)

        lab_tests = sum(len(lab_tests_by_batch.get(bid, [])) for bid in batch_ids)
        certificates = sum(len(certificates_by_batch.get(bid, [])) for bid in batch_ids)

        devices = self._repo.list_iot_devices()
        device_ids = [d.get("device_id", "") for d in devices if d.get("device_id")]

        # Bulk fetch telemetry events for all devices at once
        telemetry_events = 0
        if device_ids:
            telemetry = self._repo.list_telemetry_events_for_devices(device_ids, limit=10_000)
            telemetry_events = len(telemetry)

        harvests = self._repo.list_harvests(None)
        return {
            "registered_beekeepers": len(self._repo.list_beekeepers()),
            "organizations": len(self._repo.list_organizations()),
            "hives": len(self._repo.list_hives(None)),
            "harvests": len(harvests),
            "honey_harvested_kg": round(
                sum(float(h.get("quantity_kg", 0)) for h in harvests), 2
            ),
            "batches": len(batches),
            "lab_tests": lab_tests,
            "certificates": certificates,
            "iot_devices": len(devices),
            "telemetry_events": telemetry_events,
        }


def build_org_service(repo: Repository) -> OrgService:
    return OrgService(repo)