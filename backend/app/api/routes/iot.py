"""IoT device + telemetry ingestion routes.

Device authentication is the device's own key: a valid event signature is the
credential (exactly how a physical ESP32-class device would authenticate).
No user JWT is required to *ingest* telemetry — but device identity is bound
to a registered key, so arbitrary users cannot impersonate a device through
normal UI flows (the UI never holds device private keys).

Simulator control routes are DEMO-only (non-production), matching the tamper
routes. Device registration and status reads are normal admin operations.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from ...core.config import get_settings
from ...core.rbac import require_permission
from ...schemas import iot as iot_schemas
from ...services.iot_service import (
    DeviceNotFound,
    TelemetryRejected,
)

router = APIRouter(prefix="/api/v1", tags=["iot"])


def _sim_service(request: Request):
    return request.app.state.services.get("iot")


def _require_demo_mode(request: Request) -> None:
    settings = request.app.state.settings if hasattr(request.app.state, "settings") else get_settings()
    if settings.is_production:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="IoT simulator control is disabled in production.",
        )


def _enforce_device_scope(service, device_id: str, user) -> None:
    """Readers may only see devices they are scoped to own."""
    dev = service.get_device(device_id)
    if dev is None:
        raise HTTPException(status_code=404, detail="device not found")
    if not service.device_in_scope(user, device_id):
        raise HTTPException(status_code=403, detail="device out of scope")


# ------------------------------------------------------------------ registry
@router.get("/iot/devices", response_model=list[iot_schemas.IotDeviceRead])
def list_devices(
    request: Request,
    user=Depends(require_permission("iot.device.read")),
) -> list:
    service = request.app.state.services["iot"]["devices"]
    return service.list_devices(user)


@router.post("/iot/devices", response_model=iot_schemas.IotDeviceSignedSecrets)
def register_device(
    payload: iot_schemas.IotDeviceCreate,
    request: Request,
    user=Depends(require_permission("iot.device.create")),
) -> dict:
    service = request.app.state.services["iot"]["devices"]
    try:
        return service.register_device(
            device_name=payload.device_name,
            device_type=payload.device_type,
            firmware_version=payload.firmware_version,
            assigned_hive_id=payload.assigned_hive_id or "",
            assigned_apiary_id=payload.assigned_apiary_id or "",
            organization_id=payload.organization_id or (user.org_id or ""),
            interval_seconds=payload.interval_seconds,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/iot/devices/{device_id}", response_model=iot_schemas.IotDeviceRead)
def get_device(
    device_id: str,
    request: Request,
    user=Depends(require_permission("iot.device.read")),
) -> dict:
    service = request.app.state.services["iot"]["devices"]
    _enforce_device_scope(service, device_id, user)
    dev = service.get_device(device_id)
    if dev is None:
        raise HTTPException(status_code=404, detail="device not found")
    return dev


# -------------------------------------------------------------- ingestion
@router.post("/iot/devices/{device_id}/telemetry")
def ingest_telemetry(
    device_id: str,
    payload: iot_schemas.TelemetryEvent,
    request: Request,
) -> iot_schemas.TelemetryIngestResult:
    service = request.app.state.services["iot"]
    try:
        result = service["ingestor"].ingest_single(
            device_id, payload.model_dump(mode="json")
        )
    except DeviceNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except TelemetryRejected as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return iot_schemas.TelemetryIngestResult(**result)


@router.post("/iot/devices/{device_id}/telemetry/batch")
def ingest_telemetry_batch(
    device_id: str,
    payload: iot_schemas.TelemetryBatchRequest,
    request: Request,
) -> iot_schemas.TelemetryBatchResult:
    service = request.app.state.services["iot"]
    results = service["ingestor"].ingest_events(
        device_id, [e.model_dump(mode="json") for e in payload.events]
    )
    accepted = [r for r in results if r["accepted"]]
    rejected = [r for r in results if not r["accepted"]]
    return iot_schemas.TelemetryBatchResult(
        device_id=device_id,
        accepted=[
            iot_schemas.TelemetryAcceptItem(event_id=r["event_id"], accepted=True)
            for r in accepted
        ],
        rejected=[
            iot_schemas.TelemetryAcceptItem(event_id=r["event_id"], accepted=False, reason=r["reason"])
            for r in rejected
        ],
    )


@router.get("/iot/devices/{device_id}/telemetry")
def list_telemetry(
    device_id: str,
    request: Request,
    user=Depends(require_permission("iot.device.read")),
    limit: int = Query(default=20, ge=1, le=200),
    since: str = Query(default="", description="ISO timestamp; return events >= this"),
) -> list[iot_schemas.TelemetryEventRead]:
    service = request.app.state.services["iot"]
    _enforce_device_scope(service["devices"], device_id, user)
    rows = service["repo"].list_telemetry_events(device_id, limit=limit, since=since)
    return [row for row in rows]


@router.get("/iot/devices/{device_id}/ledger")
def device_ledger_verify(
    device_id: str,
    request: Request,
    user=Depends(require_permission("iot.device.read")),
) -> dict:
    service = request.app.state.services["iot"]
    _enforce_device_scope(service["devices"], device_id, user)
    ledger = request.app.state.services["ledger"]
    report = ledger.verify_chain(f"device:{device_id}")
    report["chain_id"] = f"device:{device_id}"
    return report


# --------------------------------------------------------- simulator (demo)
@router.post("/iot/simulator/control")
def simulator_control(
    payload: iot_schemas.SimulatorControl,
    request: Request,
    user=Depends(require_permission("iot.simulator.control")),
) -> dict:
    _require_demo_mode(request)
    if payload.action is None:
        raise HTTPException(status_code=400, detail="action is required")
    sim = request.app.state.services["iot"]["simulator"]
    devices = request.app.state.services["iot"]["devices"]
    try:
        if payload.action == "START":
            devices.set_mode(payload.device_id, payload.mode or "NORMAL")
            sim.set_mode(payload.device_id, payload.mode or "NORMAL")
            return {"device_id": payload.device_id, "action": "START", "mode": payload.mode or "NORMAL",
                    "status": sim.get_device_status(payload.device_id)}
        if payload.action == "STOP":
            devices.set_mode(payload.device_id, "STOPPED")
            sim.set_mode(payload.device_id, "STOPPED")
            return {"device_id": payload.device_id, "action": "STOP"}
        if payload.action == "PAUSE":
            devices.set_mode(payload.device_id, "PAUSED")
            sim.set_mode(payload.device_id, "PAUSED")
            return {"device_id": payload.device_id, "action": "PAUSE"}
        if payload.action == "RESUME":
            devices.set_mode(payload.device_id, "NORMAL")
            sim.set_mode(payload.device_id, "NORMAL")
            return {"device_id": payload.device_id, "action": "RESUME"}
        if payload.action == "STEP":
            event = sim.step(payload.device_id, custom=payload.custom_payload.model_dump(mode="json") if payload.custom_payload else None)
            return {"device_id": payload.device_id, "action": "STEP", "event": event}
        if payload.action == "GENERATE_EVENT":
            events = sim.generate(payload.device_id, payload.burst_count)
            return {"device_id": payload.device_id, "action": "GENERATE_EVENT",
                    "count": len(events), "events": events}
    except (DeviceNotFound, ValueError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    raise HTTPException(status_code=400, detail=f"unknown action: {payload.action}")


@router.post("/iot/simulator/mode")
def simulator_mode(
    payload: iot_schemas.SimulatorControl,
    request: Request,
    user=Depends(require_permission("iot.simulator.control")),
) -> dict:
    """Set NORMAL/ANOMALY/OFFLINE/RECOVERY/BURST/CUSTOM mode directly."""
    _require_demo_mode(request)
    if payload.mode is None:
        raise HTTPException(status_code=400, detail="mode is required")
    sim = request.app.state.services["iot"]["simulator"]
    devices = request.app.state.services["iot"]["devices"]
    try:
        sim.set_mode(payload.device_id, payload.mode)
        devices.set_mode(payload.device_id, payload.mode)
    except (DeviceNotFound, ValueError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    status_info = sim.get_device_status(payload.device_id)
    return {
        "device_id": status_info.get("device_id"),
        "mode": payload.mode,
        "device_status": status_info.get("device_status"),
        "pending_events": status_info.get("pending_events", 0),
    }


@router.get("/iot/simulator/status")
def simulator_status(
    request: Request,
    user=Depends(require_permission("iot.simulator.control")),
) -> list:
    sim = request.app.state.services["iot"]["simulator"]
    return sim.simulator_status()


@router.post("/iot/simulator/fork")
def simulator_fork(
    payload: iot_schemas.SimulatorForkTest,
    request: Request,
    user=Depends(require_permission("iot.simulator.control")),
) -> dict:
    """Run the demonstrable offline/conflict scenario (fork preserved)."""
    _require_demo_mode(request)
    sim = request.app.state.services["iot"]["simulator"]
    try:
        return sim.simulate_fork(payload.device_id)
    except DeviceNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc