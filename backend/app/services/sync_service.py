from __future__ import annotations

from typing import Any

from ..adapters.blockchain.gateway import BlockchainGateway
from ..db.supabase import Repository
from .batch_service import BatchService
from .custody_service import CustodyService
from .event_ledger import EventLedger
from .evidence_service import HarvestEvidenceService
from .harvest_service import HarvestService
from .hive_service import HiveService
from .inspection_service import InspectionService
from .treatment_service import TreatmentService
from .lab_certificate import LabCertificateService
from .lab_service import LabService
from .lineage_service import LineageService
from .passport_service import PassportService
from .assertion_service import AssertionService
from .impact_service import ProvenanceImpactService
from .reconciliation_service import ReconciliationService


class SyncService:
    """Idempotent push/pull against the backend.

    Every mutation carries the caller's stable [client_id]; accepting a client_id
    twice returns the already-stored row instead of creating a duplicate. This is
    what makes the phone's offline retry loop safe.
    """

    def __init__(
        self,
        repo: Repository,
        hive_service: HiveService,
        harvest_service: HarvestService,
        batch_service: BatchService,
        custody_service: CustodyService,
        passport_service: PassportService,
        assertion_service: Any = None,
    ) -> None:
        self._repo = repo
        self._hives = hive_service
        self._harvests = harvest_service
        self._batches = batch_service
        self._custody = custody_service
        self._passport = passport_service
        self._assertions = assertion_service

    def push_item(self, item: dict[str, Any], *, user: Any) -> dict[str, Any]:
        entity = item["entity"]
        client_id = item["client_id"]
        data = item.get("data") or {}
        try:
            if entity == "hive":
                row = self._hives.create(
                    beekeeper_id=user.user_id, data={**data, "client_id": client_id}
                )
                return {"accepted": True, "backend_id": row["id"], "client_id": client_id}
            if entity == "harvest":
                row = self._harvests.create(
                    beekeeper_id=user.user_id, data={**data, "client_id": client_id}
                )
                return {"accepted": True, "backend_id": row["id"], "client_id": client_id}
            if entity == "batch":
                row = self._batches.create(
                    data={**data, "client_id": client_id}, user=user
                )
                if "error" in row:
                    # e.g. mass-balance violation — reject the item, keep the
                    # client_id so the phone can surface the error and retry
                    # with corrected quantities. Never fabricate a backend_id.
                    return {
                        "accepted": False,
                        "client_id": client_id,
                        "error": row["error"],
                    }
                return {"accepted": True, "backend_id": row["id"], "client_id": client_id}
            if entity == "reading":
                hive = self._hives.get_for_user(data.get("hive_id", ""), user=user)
                if hive is None:
                    return {
                        "accepted": False,
                        "client_id": client_id,
                        "error": "hive not in your scope",
                    }
                row = self._hives.add_reading(hive["id"], data)
                return {"accepted": True, "backend_id": row["id"], "client_id": client_id}
            if entity == "custody":
                batch_id = data.get("batch_id", "")
                if self._batches.get_for_user(batch_id, user=user) is None:
                    return {
                        "accepted": False,
                        "client_id": client_id,
                        "error": "batch not in your scope",
                    }
                row = self._custody.add(
                    batch_id=batch_id, data=data
                )
                return {"accepted": True, "backend_id": row["id"], "client_id": client_id}
            if entity in ("quantity_assertion", "assertion"):
                return self._push_assertion(item, user=user)
        except ValueError as exc:
            return {"accepted": False, "client_id": client_id, "error": str(exc)}
        except Exception as exc:  # never let one item kill a sync pass
            return {"accepted": False, "client_id": client_id, "error": str(exc)}
        return {
            "accepted": False,
            "client_id": client_id,
            "error": f"unknown entity: {entity}",
        }

    def _push_assertion(self, item: dict[str, Any], *, user: Any) -> dict[str, Any]:
        """Offline assertion -> server ledger (idempotent by client_id)."""
        if self._assertions is None:
            return {
                "accepted": False,
                "client_id": item.get("client_id", ""),
                "error": "assertion service not configured",
            }
        data = dict(item.get("data") or {})
        data.setdefault("client_id", item.get("client_id", ""))
        return self._assertions.push_offline_assertion(data, user=user)

    def pull(self, *, user: Any) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        for hive in self._hives.list_for_user(user=user):
            items.append({"entity": "hive", "backend_id": hive["id"], "data": hive})
        for harvest in self._harvests.list_for_user(user=user):
            items.append(
                {"entity": "harvest", "backend_id": harvest["id"], "data": harvest}
            )
        for batch in self._batches.list_for_user(user=user):
            items.append({"entity": "batch", "backend_id": batch["id"], "data": batch})
        return items


def build_services(
    repo: Repository, gateway: BlockchainGateway | None = None
) -> dict[str, Any]:
    from ..adapters.blockchain.gateway import build_blockchain_gateway

    if gateway is None:
        gateway = build_blockchain_gateway()
    hive_service = HiveService(repo)
    harvest_service = HarvestService(repo)
    inspection_service = InspectionService(repo)
    treatment_service = TreatmentService(repo)
    batch_service = BatchService(repo)
    custody_service = CustodyService(repo)
    lab_service = LabService(repo)
    ledger = EventLedger(repo)
    evidence_service = HarvestEvidenceService(repo, gateway)
    lab_certificate_service = LabCertificateService(repo, gateway, ledger)
    lineage_service = LineageService(repo, ledger)
    # Evidence-linked assertions / reconciliation / impact analysis all build on
    # the SAME ledger and batch genealogy — no parallel provenance system.
    assertion_service = AssertionService(repo, ledger, gateway, batch_service)
    reconciliation_service = ReconciliationService(
        repo, assertion_service, batch_service, ledger
    )
    impact_service = ProvenanceImpactService(
        repo, batch_service, assertion_service, reconciliation_service, ledger
    )
    passport_service = PassportService(repo, batch_service, assertion_service)

    from .notification_service import NotificationService

    notifications = NotificationService(repo)

    from .platform_service import PlatformService

    platform = PlatformService(repo)

    from .iot_service import DeviceSimulator, IoTDeviceService, TelemetryIngestor

    iot_devices = IoTDeviceService(repo, ledger, notifications)
    iot_ingestor = TelemetryIngestor(repo, notifications, ledger)
    iot_simulator = DeviceSimulator(repo, iot_ingestor, ledger)

    sync_service = SyncService(
        repo,
        hive_service,
        harvest_service,
        batch_service,
        custody_service,
        passport_service,
        assertion_service,
    )
    return {
        "repo": repo,
        "hives": hive_service,
        "harvests": harvest_service,
        "inspections": inspection_service,
        "treatments": treatment_service,
        "batches": batch_service,
        "custody": custody_service,
        "labs": lab_service,
        "passport": passport_service,
        "sync": sync_service,
        "evidence": evidence_service,
        "certificates": lab_certificate_service,
        "lineage": lineage_service,
        "assertions": assertion_service,
        "reconciliation": reconciliation_service,
        "impact": impact_service,
        "ledger": ledger,
        "gateway": gateway,
        "notifications": notifications,
        "platform": platform,
        "iot": {
            "devices": iot_devices,
            "ingestor": iot_ingestor,
            "simulator": iot_simulator,
            "repo": repo,
        },
    }