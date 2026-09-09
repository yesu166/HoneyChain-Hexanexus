"""Schemas for IoT device registry + telemetry ingestion.

Truth notes:
- A telemetry event is signed by the *device* (not a person) with its own
  ECDSA key. The signature attests "this registered device produced this
  event", not that a physical sensor was honest.
- Simulation data is explicitly labeled (source=simulation, is_simulated=True)
  and can never be presented as physical IoT data.
"""
from __future__ import annotations

import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field

DeviceStatus = Literal["ONLINE", "OFFLINE", "SYNCING", "ERROR", "DISABLED"]
SimulationMode = Literal[
    "NORMAL", "ANOMALY", "OFFLINE", "RECOVERY", "BURST", "CUSTOM", "PAUSED", "STOPPED"
]


class IotDeviceCreate(BaseModel):
    device_name: str
    device_type: str = "hive-sensor"
    firmware_version: str = "1.0.0"
    assigned_hive_id: Optional[str] = None
    assigned_apiary_id: Optional[str] = None
    organization_id: str = ""
    interval_seconds: int = Field(default=300, ge=10, le=86400)


class IotDeviceRead(BaseModel):
    device_id: str
    device_name: str
    device_type: str
    firmware_version: str
    device_status: DeviceStatus = "ONLINE"
    assigned_hive_id: Optional[str]
    assigned_apiary_id: Optional[str]
    organization_id: str
    last_seen: Optional[datetime.datetime] = None
    created_at: str
    sequence: int
    event_count: int
    battery_percent: Optional[float] = None
    signal_strength: Optional[float] = None
    mode: SimulationMode = "STOPPED"
    is_simulated: bool = True
    configuration: dict = {}


class IotDeviceSignedSecrets(BaseModel):
    """Returned once at device registration so the simulator can sign events.

    The private key is the single thing that authenticates the device. It is
    never stored in API responses again after this point."""

    device_id: str
    device_public_key_pem: str
    device_private_key_pem: str
    note: str


class TelemetryPayload(BaseModel):
    temperature_c: Optional[float] = None
    humidity_percent: Optional[float] = None
    hive_weight_kg: Optional[float] = None
    bee_activity: Optional[float] = None
    acoustic_frequency_hz: Optional[float] = None
    battery_percent: Optional[float] = None
    signal_strength: Optional[float] = None
    extra: dict = {}


class TelemetryEvent(BaseModel):
    """A raw signed event exactly as a device transmits it.

    ``timestamp`` stays a plain ISO-8601 string: the device signs the exact
    bytes it sends, so the server must canonicalize the *same* representation
    or every signature would fail after a datetime round-trip."""

    event_id: str
    device_id: str
    sequence: int = Field(ge=1)
    timestamp: str
    payload: TelemetryPayload
    payload_hash: str
    previous_event_hash: str = ""
    signature: str


class TelemetryBatchRequest(BaseModel):
    """Offline-recovery upload: a queue of signed events from one device.

    Each event is validated the same way as single ingestion; duplicates are
    rejected (idempotent) and sequence gaps are reported, never auto-fixed."""

    events: list[TelemetryEvent] = Field(min_length=1, max_length=500)


class TelemetryEventRead(BaseModel):
    event_id: str
    device_id: str
    sequence: int
    timestamp: datetime.datetime
    payload: TelemetryPayload
    payload_hash: str
    previous_event_hash: str = ""
    is_simulated: bool = True
    created_at: Optional[datetime.datetime] = None


class TelemetryAcceptItem(BaseModel):
    event_id: str
    accepted: bool
    reason: str = ""


class TelemetryBatchResult(BaseModel):
    device_id: str
    accepted: list[TelemetryAcceptItem]
    rejected: list[TelemetryAcceptItem]


class TelemetryIngestResult(BaseModel):
    event_id: str
    device_id: str
    accepted: bool
    sequence: int
    reason: str = ""
    hive_id: Optional[str] = None
    alert_triggered: bool = False


class SimulatorControl(BaseModel):
    action: Optional[Literal["START", "STOP", "PAUSE", "RESUME", "STEP", "GENERATE_EVENT"]] = None
    device_id: str
    mode: Optional[SimulationMode] = None
    burst_count: int = Field(default=10, ge=1, le=200)
    custom_payload: Optional[TelemetryPayload] = None


class SimulatorForkTest(BaseModel):
    device_id: str


class DeviceTelemetryQuery(BaseModel):
    limit: int = Field(default=20, ge=1, le=200)
    since: Optional[datetime.datetime] = None