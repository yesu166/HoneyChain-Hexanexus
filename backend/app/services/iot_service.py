"""IoT device registry, telemetry ingestion and the software IoT simulator.

Single ingestion pathway
------------------------
Physical ESP32-class devices and the in-app simulator both call
``IoTDeviceService.ingest_events`` (exposed as ``POST /api/v1/iot/devices/
{device_id}/telemetry`` and the ``/batch`` form). Validation is identical:

- device must exist and not be DISABLED
- event_id must be unique (duplicates rejected, never overwritten)
- sequence must be the next expected value (gaps reported, never auto-fixed)
- payload_hash must match the canonical payload
- signature must verify against the device's registered public key

Simulator honesty
-----------------
The simulator is a *development/test device implementation*. It generates
realistic temporal telemetry, signs it with the same *device* keys the
ingestion layer validates against, and pushes it through the real pipeline.
It never claims to be physical hardware: every telemetry row is labeled
``is_simulated=True`` (mirrored as ``source='simulation'`` in hive readings)
and surfaced in every admin/demo screen.

Fork/conflict demo
------------------
``simulate_fork`` appends two explicit branches at the same chain head so the
event ledger keeps BOTH heads and records a ``fork`` marker (the project's
defined conflict policy). No event is ever silently overwritten.
"""
from __future__ import annotations

import base64
import hashlib
from typing import Any

from ..core.crypto import (
    canonical_json,
    generate_signing_key,
    public_key_hex,
    serialize_private_key_pem,
    serialize_public_key_pem,
    sha256_bytes,
)
from ..core.security import CurrentUser
from ..db.supabase import Repository
from .event_ledger import EventLedger
from .honeychain_ml_service import HoneyChainML

SIM_MODES = ("NORMAL", "TEMPERATURE_STRESS", "HUMIDITY_STRESS", "WEIGHT_CHANGE", "ACOUSTIC_CHANGE", "COMBINED_STRESS", "PERSISTENT_ANOMALY", "SENSOR_FAULT", "RECOVERY", "OFFLINE", "RESET", "BURST", "CUSTOM")
DEVICE_STATUSES = ("ONLINE", "OFFLINE", "SYNCING", "ERROR", "DISABLED")


class DeviceNotFound(ValueError):
    pass


class TelemetryRejected(ValueError):
    pass


class SequenceGap(TelemetryRejected):
    pass


class DuplicateEvent(TelemetryRejected):
    pass


class InvalidSignature(TelemetryRejected):
    pass


class InvalidPayloadHash(TelemetryRejected):
    pass


def _now_iso() -> str:
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).isoformat()


def hash_payload_json(payload: dict[str, Any]) -> str:
    return sha256_bytes(canonical_json(payload).encode("utf-8"))


def device_chain_hash(sequence: int, payload_hash: str) -> str:
    """Per-device hash chain: hash of (sequence, payload_hash) of the previous
    event. Devices that chain from stored events make that chain verifiable."""
    return sha256_bytes(
        canonical_json({"sequence": sequence, "payload_hash": payload_hash}).encode("utf-8")
    )


def _sign_canonical(payload: dict[str, Any], key_pem: str) -> bytes:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    key = serialization.load_pem_private_key(key_pem.encode("utf-8"), password=None)
    canonical = canonical_json(payload).encode("utf-8")
    return key.sign(canonical, ec.ECDSA(hashes.SHA256()))


def _verify_event(ev: dict[str, Any], public_key_pem: str) -> bool:
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    try:
        der = base64.b64decode(ev.get("signature", "").encode("ascii"))
        public_key = serialization.load_pem_public_key(public_key_pem.encode("utf-8"))
        canonical = canonical_json(_signed_fields(ev)).encode("utf-8")
        public_key.verify(der, canonical, ec.ECDSA(hashes.SHA256()))
        return True
    except (InvalidSignature, ValueError, TypeError, KeyError):
        return False


def _signed_fields(ev: dict[str, Any]) -> dict[str, Any]:
    return {
        "event_id": ev["event_id"],
        "device_id": ev["device_id"],
        "sequence": ev["sequence"],
        "timestamp": ev["timestamp"],
        "payload": ev["payload"],
        "payload_hash": ev.get("payload_hash", ""),
        "previous_event_hash": ev.get("previous_event_hash", ""),
    }


# ---------------------------------------------------------------------------
# Device registry
# ---------------------------------------------------------------------------

class IoTDeviceService:
    def __init__(
        self,
        repo: Repository,
        ledger: EventLedger,
        notifications: Any,
    ) -> None:
        self._repo = repo
        self._ledger = ledger
        self._notifications = notifications

    # ------------------------------------------------------------ registry
    def register_device(
        self,
        *,
        device_name: str,
        device_type: str,
        firmware_version: str,
        assigned_hive_id: str = "",
        assigned_apiary_id: str = "",
        organization_id: str = "",
        interval_seconds: int = 300,
    ) -> dict[str, Any]:
        key = generate_signing_key()
        public_pem = serialize_public_key_pem(key.public_key())
        private_pem = serialize_private_key_pem(key)
        device_id = "HC-SIM-" + public_key_hex(key.public_key())[:10]
        device = {
            "device_id": device_id,
            "device_name": device_name or device_id,
            "device_type": device_type or "hive-sensor",
            "firmware_version": firmware_version or "1.0.0",
            "device_status": "ONLINE",
            "assigned_hive_id": assigned_hive_id or None,
            "assigned_apiary_id": assigned_apiary_id or None,
            "organization_id": organization_id,
            "device_public_key_pem": public_pem,
            "device_private_key_pem": private_pem,
            "created_at": _now_iso(),
            "sequence": 0,
            "event_count": 0,
            "battery_percent": 100.0,
            "signal_strength": -60.0,
            "mode": "STOPPED",
            "is_simulated": True,
            "interval_seconds": interval_seconds,
            "configuration": {},
        }
        self._repo.create_iot_device(dict(device))
        return {
            **{k: v for k, v in device.items() if k != "device_private_key_pem"},
            "device_public_key_pem": public_pem,
            "device_private_key_pem": private_pem,
            "note": "private key shown once; keep it out of the repository",
        }

    def list_devices(self, user: CurrentUser | None = None) -> list[dict[str, Any]]:
        if user and user.role in ("admin", "institution"):
            return [self._strip(d) for d in self._repo.list_iot_devices()]
        org = user.org_id if user else ""
        return [self._strip(d) for d in self._repo.list_iot_devices(org)]

    def get_device(self, device_id: str) -> dict[str, Any] | None:
        dev = self._repo.get_iot_device(device_id)
        return self._strip(dev) if dev else None

    def device_in_scope(self, user: CurrentUser | None, device_id: str) -> bool:
        """Role-scoped read rule: admin/institution any; beekeeper owns the
        assigned hive; fpo/processor/lab/buyer org match."""
        if user is None:
            return True
        dev = self._repo.get_iot_device(device_id)
        if dev is None:
            return False
        if user.role in ("admin", "institution"):
            return True
        if user.role == "beekeeper":
            hive_ids = {h["id"] for h in self._repo.list_hives(user.user_id)}
            return dev.get("assigned_hive_id") in hive_ids
        return dev.get("organization_id") == user.org_id

    def get_device_signing_key(self, device_id: str) -> str | None:
        dev = self._repo.get_iot_device(device_id)
        if dev is None:
            return None
        return dev.get("device_private_key_pem")

    def set_mode(self, device_id: str, mode: str) -> dict[str, Any]:
        if mode not in ("STOPPED", "PAUSED") + SIM_MODES:
            raise ValueError(f"unknown simulation mode: {mode}")
        dev = self._repo.get_iot_device(device_id)
        if dev is None:
            raise DeviceNotFound(device_id)
        self._repo.update_iot_device(device_id, {"mode": mode})
        if mode == "NORMAL":
            self._repo.update_iot_device(device_id, {"device_status": "ONLINE"})
        return self.get_device(device_id)

    @staticmethod
    def _strip(dev: dict[str, Any]) -> dict[str, Any]:
        return {k: v for k, v in dev.items() if k != "device_private_key_pem"}

    # ------------------------------------------------------------ signing
    @staticmethod
    def signed_event(event: dict[str, Any], key_pem: str) -> dict[str, Any]:
        payload = event["payload"]
        event["payload_hash"] = hash_payload_json(payload)
        event["signature"] = base64.b64encode(
            _sign_canonical(_signed_fields(event), key_pem)
        ).decode("ascii")
        return event


# ---------------------------------------------------------------------------
# Telemetry ingestion (the single pathway)
# ---------------------------------------------------------------------------

class TelemetryIngestor:
    """Shared validation+persistence path used by single-, batch- and
    simulator feeds. Physical devices and the simulator are identical here."""

    def __init__(
        self,
        repo: Repository,
        notifications: Any,
        ledger: EventLedger,
    ) -> None:
        self._repo = repo
        self._notifications = notifications
        self._ledger = ledger

    def ingest_events(
        self, device_id: str, events: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        results = []
        for ev in sorted(events, key=lambda e: int(e.get("sequence", 0))):
            try:
                result = self.ingest_single(device_id, ev)
            except TelemetryRejected as exc:
                result = {
                    "event_id": ev.get("event_id", ""),
                    "device_id": device_id,
                    "accepted": False,
                    "sequence": ev.get("sequence", 0),
                    "reason": str(exc),
                }
            results.append(result)
        return results

    def ingest_single(self, device_id: str, ev: dict[str, Any]) -> dict[str, Any]:
        device = self._repo.get_iot_device(device_id)
        if device is None:
            raise DeviceNotFound(device_id)
        if device.get("device_status") == "DISABLED":
            raise TelemetryRejected("device DISABLED")

        event_id = ev.get("event_id", "")
        sequence = int(ev.get("sequence", 0))
        payload = ev.get("payload") or {}
        if isinstance(payload, dict):
            # The device signs exactly the fields it sent. Pydantic model_dump
            # injects None-valued keys and an empty "extra"; drop them so the
            # server canonicalizes byte-identical to what was signed.
            payload = {
                k: v
                for k, v in payload.items()
                if v is not None and not (k == "extra" and not v)
            }
            ev["payload"] = payload
        ts = ev.get("timestamp")

        if event_id and self._repo.get_telemetry_event(event_id) is not None:
            self._notifications.note_rejected(device, "sequence", f"duplicate event {event_id}", title="Duplicate event")
            raise DuplicateEvent(f"duplicate event: {event_id}")

        provided_hash = ev.get("payload_hash", "")
        computed_hash = hash_payload_json(payload)
        if provided_hash and provided_hash != computed_hash:
            self._notifications.note_rejected(device, "integrity", "payload_hash mismatch", title="Payload integrity")
            raise InvalidPayloadHash("payload_hash mismatch")

        expected = int(device.get("sequence", 0)) + 1
        if sequence > expected:
            self._notifications.note_rejected(device, "sequence", f"sequence gap: got {sequence}, expected {expected}", title="Sequence gap")
            raise SequenceGap(f"sequence gap: got {sequence}, expected {expected}")
        if sequence <= int(device.get("sequence", 0)):
            self._notifications.note_rejected(device, "sequence", f"replayed/repeated sequence {sequence}", title="Duplicate event")
            raise DuplicateEvent(f"sequence {sequence} already seen")

        sig_pem = device.get("device_public_key_pem", "")
        if sig_pem and not _verify_event(ev, sig_pem):
            self._notifications.note_rejected(device, "integrity", "signature invalid", title="Invalid signature")
            raise InvalidSignature("signature invalid")

        row = {
            "event_id": event_id or f"{device_id}-{sequence}",
            "device_id": device_id,
            "sequence": sequence,
            "timestamp": ts,
            "payload": payload,
            "payload_hash": computed_hash,
            "previous_event_hash": ev.get("previous_event_hash", ""),
            "hive_id": device.get("assigned_hive_id") or None,
            "organization_id": device.get("organization_id", ""),
            "signature": ev.get("signature", ""),
            "is_simulated": bool(device.get("is_simulated", True)),
            "created_at": _now_iso(),
        }
        self._repo.add_telemetry_event(row)
        self._repo.update_iot_device(
            device_id,
            {
                "sequence": sequence,
                "event_count": int(device.get("event_count", 0)) + 1,
                "last_seen": ts,
                "device_status": "ONLINE",
                "battery_percent": payload.get("battery_percent") or device.get("battery_percent", 100.0),
                "signal_strength": payload.get("signal_strength") or device.get("signal_strength", -60.0),
            },
        )
        if row["hive_id"]:
            source = "iot" if not row["is_simulated"] else "simulation"
            self._repo.add_reading(
                {
                    "hive_id": row["hive_id"],
                    "temperature_c": payload.get("temperature_c"),
                    "humidity_percent": payload.get("humidity_percent"),
                    "weight_kg": payload.get("hive_weight_kg"),
                    "recorded_at": ts,
                    "source": source,
                }
            )
        self._ledger.append(
            chain_id=f"device:{device_id}",
            event_type="telemetry",
            entity_ref=row["event_id"],
            payload={
                "sequence": sequence,
                "payload_hash": computed_hash,
                "hive_id": row["hive_id"],
            },
            device_id=device_id,
            ts=ts,
        )
        ml_result = self._ml.ingest(device_id, payload, timestamp=ts)
        alert_triggered = self._notifications.evaluate(device, row)
        return {
            "event_id": row["event_id"],
            "device_id": device_id,
            "accepted": True,
            "sequence": sequence,
            "hive_id": row["hive_id"],
            "alert_triggered": alert_triggered,
            "ml_status": ml_result.get("status"),
            "ml_score": ml_result.get("score"),
            "ml_anomaly": bool(ml_result.get("ml_anomaly", False)),
            "ml_evidence": ml_result.get("evidence", []),
            "ml_reason": ml_result.get("reason", ""),
            "ml_recommendation": ml_result.get("recommendation", ""),
            "ml_persistence_observations": int(ml_result.get("persistence_observations", 0)),
            "reason": "",
        }


    @property
    def ml_engine(self) -> HoneyChainML:
        return self._ml


# ---------------------------------------------------------------------------
# Software IoT simulator
# ---------------------------------------------------------------------------

class DeviceSimulator:
    """Configurable software IoT device emitting realistic temporal telemetry.

    Values have *state* (temperature drifts, weight changes slowly, battery
    decays, signal wobbles, pre-harvest anomalies) instead of random noise.
    Generated events are signed with the registered device key and submitted
    through the real ingestion path.

    OFFLINE mode queues events locally (device_status=OFFLINE); RECOVERY
    flushes the queue through the same ingestion path (SYNCING -> ONLINE) so
    the UI can show real pending/synced/remaining counts — never a faked
    refresh.
    """

    def __init__(self, repo: Repository, ingestor: TelemetryIngestor, ledger: EventLedger) -> None:
        self._repo = repo
        self._ingestor = ingestor
        self._ledger = ledger
        self._ml = HoneyChainML()
        self._state: dict[str, dict[str, Any]] = {}
        self._queue: dict[str, list[dict[str, Any]]] = {}

    def _state_for(self, device_id: str) -> dict[str, Any]:
        state = self._state.setdefault(device_id, {})
        if not state:
            state.update(
                {
                    "temp": 24.0 + (_rng(device_id, 1) % 80) / 10 - 4.0,
                    "humidity": 55.0 + (_rng(device_id, 2) % 200) / 10 - 10.0,
                    "weight": 12.0 + (_rng(device_id, 3) % 50) / 10,
                    "activity": 60.0 + (_rng(device_id, 4) % 30),
                    "battery": 100.0,
                    "signal": -60.0,
                    "acoustic": 210.0,
                    "anomaly": False,
                    "mode": "NORMAL",
                    "t": 0,
                }
            )
        return state

    def set_mode(self, device_id: str, mode: str) -> dict[str, Any]:
        state = self._state_for(device_id)
        state["mode"] = mode
        if mode == "ANOMALY":
            state["anomaly"] = True
        elif mode == "NORMAL":
            state["anomaly"] = False
        elif mode == "RECOVERY":
            self._flush_offline(device_id)
            self._repo.update_iot_device(device_id, {"device_status": "ONLINE"})
        return self.get_device_status(device_id)

    def get_device_status(self, device_id: str) -> dict[str, Any]:
        dev = self._repo.get_iot_device(device_id)
        if dev is None:
            raise DeviceNotFound(device_id)
        out = {k: v for k, v in dev.items() if k != "device_private_key_pem"}
        out["pending_events"] = len(self._queue.get(device_id, []))
        return out

    def step(self, device_id: str, *, custom: dict[str, Any] | None = None) -> dict[str, Any]:
        dev = self._repo.get_iot_device(device_id)
        if dev is None:
            raise DeviceNotFound(device_id)
        state = self._state_for(device_id)
        mode = dev.get("mode", "STOPPED")

        if mode in ("STOPPED", "PAUSED"):
            return {"device_id": device_id, "paused": True, "queued": False}

        state["t"] += 1

        drift = (_rng(device_id, 5 + state["t"] % 7) / 100.0) - 0.12
        if state["anomaly"]:
            state["temp"] = min(42.0, state["temp"] + 0.5)
            state["humidity"] = min(99.0, state["humidity"] + 1.2)
            state["weight"] = max(1.0, state["weight"] - 0.6)
            state["activity"] = max(5.0, state["activity"] - 3.5)
        else:
            state["temp"] = min(38.0, max(14.0, state["temp"] + drift))
            state["humidity"] = min(90.0, max(25.0, state["humidity"] + (_rng(device_id, 6 + state["t"] % 5) / 40.0 - 0.3)))
            state["weight"] = max(0.5, state["weight"] + (_rng(device_id, 7 + state["t"] % 5) / 100.0 - 0.05))
            state["activity"] = min(100.0, max(10.0, state["activity"] + (_rng(device_id, 8 + state["t"] % 5) / 10.0 - 0.5)))
        state["battery"] = max(2.0, state["battery"] - 0.05)
        state["signal"] = min(-40.0, max(-95.0, state["signal"] + (_rng(device_id, 9) / 10.0 - 0.5)))
        state["acoustic"] = min(420.0, max(150.0, state["acoustic"] + (4.0 if state["anomaly"] else 0.05)))

        payload = {
            "temperature_c": round(state["temp"], 2),
            "humidity_percent": round(state["humidity"], 2),
            "hive_weight_kg": round(state["weight"], 2),
            "bee_activity": round(state["activity"], 2),
            "acoustic_frequency_hz": round(state["acoustic"], 2),
            "battery_percent": round(state["battery"], 2),
            "signal_strength": round(state["signal"], 2),
        }
        if custom:
            merged = dict(payload)
            for key, val in (custom or {}).items():
                if val is not None and key != "extra":
                    merged[key] = val
            payload = merged

        from datetime import datetime, timedelta, timezone

        queued_count = len(self._queue.get(device_id, []))
        sequence = int(dev.get("sequence", 0)) + 1 + queued_count
        timestamp = (datetime.now(timezone.utc) + timedelta(seconds=_rng(device_id, 10) // 60)).isoformat()

        last = self._repo.list_telemetry_events(device_id, limit=1)
        previous_hash = device_chain_hash(int(last[0]["sequence"]), last[0]["payload_hash"]) if last else ""

        event = {
            "event_id": f"{device_id}-{sequence}",
            "device_id": device_id,
            "sequence": sequence,
            "timestamp": timestamp,
            "payload": payload,
            "payload_hash": "",
            "previous_event_hash": previous_hash,
            "signature": "",
        }
        key_pem = self._repo.get_iot_device(device_id).get("device_private_key_pem")
        if key_pem:
            event = IoTDeviceService.signed_event(event, key_pem)

        if mode == "OFFLINE":
            # queue locally; do NOT touch the network path while offline
            self._queue.setdefault(device_id, []).append(event)
            self._repo.update_iot_device(
                device_id,
                {"device_status": "OFFLINE", "last_seen": None},
            )
            return {**event, "queued": True}
        return self._ingestor.ingest_single(device_id, event)

    def generate(self, device_id: str, count: int = 10) -> list[dict[str, Any]]:
        out = []
        for _ in range(count):
            try:
                out.append(self.step(device_id))
            except (TelemetryRejected, ValueError):
                continue
        return out

    def _flush_offline(self, device_id: str) -> int:
        queued = self._queue.get(device_id, [])
        if not queued:
            return 0
        self._repo.update_iot_device(device_id, {"device_status": "SYNCING"})
        results = self._ingestor.ingest_events(device_id, queued)
        accepted = sum(1 for r in results if r["accepted"])
        self._queue[device_id] = []
        return accepted

    def simulate_fork(self, device_id: str) -> dict[str, Any]:
        """Demonstrable conflict scenario.

        Events 1..3 append normally; then two branches diverge at the same
        chain head. The ledger preserves both and records a ``fork`` marker.
        ``verify_chain`` reports both heads with integrity intact."""
        for _ in range(3):
            self.step(device_id)
        chain = f"device:{device_id}"
        head = self._ledger.head_hash(chain)
        ev_a = self._ledger.append(
            chain_id=chain,
            event_type="telemetry",
            entity_ref=f"{device_id}-4A",
            payload={"branch": "A", "seq": "4A", "prev": head},
            device_id=device_id,
            prev_hash=head,
            ts=_now_iso(),
        )
        ev_b = self._ledger.append(
            chain_id=chain,
            event_type="telemetry",
            entity_ref=f"{device_id}-4B",
            payload={"branch": "B", "seq": "4B", "prev": head},
            device_id=device_id,
            prev_hash=head,
            ts=_now_iso(),
        )
        report = self._ledger.verify_chain(chain)
        report["conflict"] = {
            "detected": True,
            "branch_a_hash": ev_a.hash,
            "branch_b_hash": ev_b.hash,
            "heads": [e.hash for e in self._ledger.chain_heads(chain)],
            "policy": "fork preserved and surfaced; neither branch dropped",
        }
        return report

    def simulator_status(self) -> list[dict[str, Any]]:
        out = []
        for d in self._repo.list_iot_devices():
            out.append(
                {
                    "device_id": d["device_id"],
                    "device_name": d.get("device_name", ""),
                    "device_status": d.get("device_status", "OFFLINE"),
                    "mode": d.get("mode", "STOPPED"),
                    "assigned_hive_id": d.get("assigned_hive_id"),
                    "organization_id": d.get("organization_id", ""),
                    "sequence": d.get("sequence", 0),
                    "event_count": d.get("event_count", 0),
                    "battery_percent": d.get("battery_percent"),
                    "signal_strength": d.get("signal_strength"),
                    "last_seen": d.get("last_seen"),
                    "pending_events": len(self._queue.get(d["device_id"], [])),
                    "is_simulated": bool(d.get("is_simulated", True)),
                }
            )
        return out


def _rng(seed: str, salt: int) -> int:
    """Cheap deterministic pseudo-random for reproducible simulations.

    Returns 0..999 so callers can treat it as a bounded unit (e.g. divide for
    drift); anything needing a wider range applies a ``%`` of its own.
    """
    digest = hashlib.sha256(f"{seed}:{salt}".encode("utf-8")).hexdigest()
    return int(digest[:8], 16) % 1000