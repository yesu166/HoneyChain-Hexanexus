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
from .lab_certificate import LabCertificateService
from .lab_service import LabService
from .lineage_service import LineageService
from .passport_service import PassportService


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
    ) -> None:
        self._repo = repo
        self._hives = hive_service
        self._harvests = harvest_service
        self._batches = batch_service
        self._custody = custody_service
        self._passport = passport_service

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
        except ValueError as exc:
            return {"accepted": False, "client_id": client_id, "error": str(exc)}
        except Exception as exc:  # never let one item kill a sync pass
            return {"accepted": False, "client_id": client_id, "error": str(exc)}
        return {
            "accepted": False,
            "client_id": client_id,
            "error": f"unknown entity: {entity}",
        }

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
    batch_service = BatchService(repo)
    custody_service = CustodyService(repo)
    lab_service = LabService(repo)
    passport_service = PassportService(repo, batch_service)
    ledger = EventLedger(repo)
    evidence_service = HarvestEvidenceService(repo, gateway)
    lab_certificate_service = LabCertificateService(repo, gateway, ledger)
    lineage_service = LineageService(repo, ledger)

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
    )
    return {
        "repo": repo,
        "hives": hive_service,
        "harvests": harvest_service,
        "batches": batch_service,
        "custody": custody_service,
        "labs": lab_service,
        "passport": passport_service,
        "sync": sync_service,
        "evidence": evidence_service,
        "certificates": lab_certificate_service,
        "lineage": lineage_service,
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