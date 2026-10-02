"""Canonical batch provenance aggregation.

`GET /api/v1/batches/{batch_id}/provenance` must be able to answer, in one call,
where a batch came from (material lineage: hive -> harvest -> batch -> split /
merge) and what happened to it operationally (collection -> lab -> certificate
-> processing -> packaging -> custody -> buyer -> passport).

This service only AGGREGATES records that already exist; it never invents a
stage. A missing stage stays missing, and the blockchain anchor is reported
exactly as the repository stored it.
"""
from __future__ import annotations

from typing import Any

from ..db.supabase import Repository
from .batch_service import BatchService


class ProvenanceService:
    def __init__(self, repo: Repository, batch_service: BatchService) -> None:
        self._repo = repo
        self._batches = batch_service

    def build(self, batch_id: str) -> dict[str, Any] | None:
        batch = self._repo.get_batch(batch_id)
        if batch is None:
            return None

        harvest_sources: list[dict[str, Any]] = []
        hive_sources: list[dict[str, Any]] = []
        allocated_kg = 0.0
        for link in self._repo.list_batch_harvests(batch_id):
            harvest = self._repo.get_harvest(link.get("harvest_id"))
            if not harvest:
                continue
            link_qty = float(link.get("quantity_kg", 0) or 0)
            allocated_kg += link_qty
            harvest_sources.append(
                {
                    "harvest_id": harvest.get("id"),
                    "hive_id": harvest.get("hive_id"),
                    "beekeeper_id": harvest.get("beekeeper_id"),
                    "harvested_at": harvest.get("harvested_at"),
                    "quantity_kg": harvest.get("quantity_kg"),
                    "allocated_kg": link_qty,
                    "honey_type": harvest.get("honey_type"),
                    "location": harvest.get("location"),
                }
            )
            hive = self._repo.get_hive(harvest.get("hive_id"))
            if hive:
                hive_sources.append(
                    {
                        "hive_id": hive.get("id"),
                        "hive_code": hive.get("hive_code"),
                        "beekeeper_id": hive.get("beekeeper_id"),
                        "location": hive.get("location"),
                        "status": hive.get("status"),
                    }
                )

        relations = [
            {
                "parent_batch_id": rel.get("parent_batch_id"),
                "child_batch_id": rel.get("child_batch_id"),
                "relation_type": rel.get("relation_type"),
                "quantity_kg": rel.get("quantity_kg"),
            }
            for rel in self._repo.list_batch_relations(batch_id, direction="both")
        ]

        custody = self._repo.list_custody_events(batch_id)
        lab_tests = self._repo.list_lab_tests(batch_id)
        certificates = self._repo.list_certificates(batch_id)
        anchor = self._repo.get_anchor(batch_id) or {}

        batch_qty = float(batch.get("quantity_kg", 0) or 0)
        mass_balance = {
            "batch_quantity_kg": batch_qty,
            "allocated_kg": round(allocated_kg, 6),
            "unallocated_kg": round(batch_qty - allocated_kg, 6),
            "balanced": abs(batch_qty - allocated_kg) <= 1e-6,
        }

        timeline: list[dict[str, Any]] = []
        for source in harvest_sources:
            timeline.append(
                {
                    "stage": "HARVEST",
                    "at": source.get("harvested_at"),
                    "ref": source.get("harvest_id"),
                    "detail": source.get("honey_type"),
                }
            )
        for event in custody:
            timeline.append(
                {
                    "stage": event.get("action"),
                    "at": event.get("event_at"),
                    "ref": event.get("id"),
                    "actor": event.get("actor"),
                    "detail": event.get("notes"),
                }
            )
        for test in lab_tests:
            timeline.append(
                {
                    "stage": "LAB_RESULT" if test.get("tested_at") else "LAB_REQUEST",
                    "at": test.get("tested_at") or test.get("requested_at"),
                    "ref": test.get("id"),
                    "detail": test.get("result") or test.get("status"),
                }
            )
        for cert in certificates:
            timeline.append(
                {
                    "stage": "CERTIFICATE",
                    "at": cert.get("issued_at"),
                    "ref": cert.get("certificate_id"),
                    "detail": cert.get("status"),
                }
            )
        timeline.sort(key=lambda row: str(row.get("at") or ""))

        return {
            "batch": batch,
            "harvest_sources": harvest_sources,
            "hive_sources": hive_sources,
            "relations": relations,
            "custody": custody,
            "lab_tests": lab_tests,
            "certificates": certificates,
            "anchor": anchor,
            "mass_balance": mass_balance,
            "timeline": timeline,
            "genealogy": self._batches.genealogy(batch_id),
        }
