from __future__ import annotations

from typing import Any

from ..db.supabase import Repository
from .batch_service import BatchService


class PassportService:
    """Public, unauthenticated passport resolution.

    Only public fields leave this service: no phones, emails, KYC, internal
    keys or credentials. Blockchain anchoring is reported as tamper-evidence —
    never as a purity/health certificate.
    """

    def __init__(
        self,
        repo: Repository,
        batch_service: BatchService,
        assertion_service: Any = None,
    ) -> None:
        self._repo = repo
        self._batches = batch_service
        # Optional: lets the passport report the CURRENT verification picture
        # (derived from the assertion ledger) instead of a stale cached verdict.
        self._assertions = assertion_service

    def resolve(self, subject_code: str) -> dict[str, Any] | None:
        batch = self._repo.get_batch_by_code(subject_code)
        if batch is None:
            return None

        # A persisted passport is a cache, not the source of truth. Custody
        # events, lab results and blockchain anchors arrive AFTER the first
        # resolve; serving the cached payload forever would freeze the passport
        # at its earliest state and hide real provenance from consumers.
        # Always rebuild from live records (cheap, derived state) and refresh
        # the stored copy so external references stay current.
        payload = self._build(batch)
        self._repo.save_passport(
            {
                "subject_type": "batch",
                "subject_code": subject_code,
                "payload": payload,
            }
        )
        return payload

    def _build(self, batch: dict[str, Any]) -> dict[str, Any]:
        batch_id = batch["id"]
        events = []
        for custody in self._repo.list_custody_events(batch_id):
            events.append(
                {
                    "type": custody.get("action", ""),
                    "at": custody.get("event_at"),
                    "actor": custody.get("actor", ""),
                    "detail": custody.get("notes", ""),
                }
            )
        for link in self._repo.list_batch_harvests(batch_id):
            harvest = self._repo.get_harvest(link.get("harvest_id"))
            if harvest:
                events.insert(
                    0,
                    {
                        "type": "HARVEST",
                        "at": harvest.get("harvested_at"),
                        "actor": harvest.get("beekeeper_id", ""),
                        "detail": f"{harvest.get('quantity_kg')} kg · {harvest.get('honey_type', '')}",
                    },
                )

        tests = self._repo.list_lab_tests(batch_id)
        latest = tests[-1] if tests else None
        verification = None
        if latest:
            verification = {
                "lab_id": latest.get("lab_id") or "",
                "result": latest.get("result") or "",
                "tested_by": latest.get("tested_by") or "",
                "tested_at": latest.get("tested_at"),
            }
            if latest.get("status") == "passed":
                events.append(
                    {
                        "type": "QUALITY_TEST",
                        "at": latest.get("tested_at"),
                        "actor": latest.get("tested_by", ""),
                        "detail": "Lab result: PASS",
                    }
                )

        anchor = self._repo.get_anchor(batch_id)
        anchor_payload = (
            {
                "data_hash": anchor.get("data_hash") or "",
                "tx_hash": anchor.get("tx_hash") or "",
                "chain_status": anchor.get("chain_status") or "none",
                "anchored_at": anchor.get("anchored_at"),
            }
            if anchor
            else {
                "data_hash": "",
                "tx_hash": "",
                "chain_status": "none",
                "anchored_at": None,
            }
        )
        if anchor and anchor.get("chain_status") == "anchored":
            events.append(
                {
                    "type": "ANCHOR",
                    "at": anchor.get("anchored_at"),
                    "actor": "blockchain",
                    "detail": "Record anchored (tamper-evidence).",
                }
            )

        return {
            "subject": "batch",
            "subject_code": batch.get("batch_code", ""),
            "batch_code": batch.get("batch_code", ""),
            "honey_type": batch.get("honey_type", ""),
            "origin": batch.get("origin", ""),
            "quantity_kg": batch.get("quantity_kg", 0),
            "trust_tier": batch.get("trust_tier", "self_declared"),
            "events": events,
            "verification": verification,
            "anchor": anchor_payload,
            "genealogy": self._batches.genealogy_codes(batch_id),
        }