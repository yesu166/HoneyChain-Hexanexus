"""IoT pipeline tests: device registry, signature validation, the single
ingestion pathway (simulator AND manual signed events), offline/recovery sync,
the demonstrable fork/conflict scenario, and simulator RBAC gating.

No fake pathway: every accepted event is verified (signature + payload hash +
sequence + uniqueness) exactly like a physical device would be.
"""
from __future__ import annotations

from app.services.iot_service import IoTDeviceService, hash_payload_json
from tests.conftest import auth

TS = "2026-09-09T10:00:00+00:00"


def _register(client, admin_token, hive_id="", org="ORG-TN-001"):
    resp = client.post(
        "/api/v1/iot/devices",
        headers=auth(admin_token),
        json={
            "device_name": "HC-SIM-HIVE-001",
            "device_type": "hive-sensor",
            "firmware_version": "1.3.0",
            "assigned_hive_id": hive_id,
            "organization_id": org,
            "interval_seconds": 300,
        },
    )
    assert resp.status_code == 200, resp.text
    return resp.json()


def _signed(client, secrets, payload, sequence=1, timestamp=TS, event_id=""):
    event = {
        "event_id": event_id or f"{secrets['device_id']}-{sequence}",
        "device_id": secrets["device_id"],
        "sequence": sequence,
        "timestamp": timestamp,
        "payload": payload,
    }
    return IoTDeviceService.signed_event(event, secrets["device_private_key_pem"])


# ---------------------------------------------------------------- registry


def test_register_device_reveals_signing_identity(client, admin_token):
    dev = _register(client, admin_token)
    assert dev["device_id"].startswith("HC-SIM-")
    assert dev["device_public_key_pem"].startswith("-----BEGIN PUBLIC KEY-----")
    assert dev["device_private_key_pem"].startswith("-----BEGIN PRIVATE KEY-----")
    listed = client.get("/api/v1/iot/devices", headers=auth(admin_token))
    assert any(d["device_id"] == dev["device_id"] for d in listed.json())


def test_register_device_forbidden_for_beekeeper(client, demo_token):
    resp = client.post(
        "/api/v1/iot/devices",
        headers=auth(demo_token),
        json={"device_name": "intruder"},
    )
    assert resp.status_code == 403


def test_device_read_scope(client, demo_token, fpo_token, admin_token):
    dev = _register(client, admin_token)
    assert client.get(
        f"/api/v1/iot/devices/{dev['device_id']}", headers=auth(admin_token)
    ).status_code == 200
    # FPO (same org) may read it
    got = client.get(
        f"/api/v1/iot/devices/{dev['device_id']}", headers=auth(fpo_token)
    )
    assert got.status_code == 200
    # Beekeeper may not read a device that is not on their hive
    got = client.get(
        f"/api/v1/iot/devices/{dev['device_id']}", headers=auth(demo_token)
    )
    assert got.status_code == 403


def test_beekeeper_can_read_device_on_own_hive(client, demo_token, admin_token):
    hive = client.post(
        "/api/v1/hives", headers=auth(demo_token), json={"hive_code": "HIVE-IOT1"}
    ).json()
    dev = _register(client, admin_token, hive_id=hive["id"])
    got = client.get(
        f"/api/v1/iot/devices/{dev['device_id']}", headers=auth(demo_token)
    )
    assert got.status_code == 200


# ------------------------------------------------------------- telemetry


def test_ingest_accepted_event_creates_reading(client, demo_token, admin_token):
    hive = client.post(
        "/api/v1/hives", headers=auth(demo_token), json={"hive_code": "HIVE-I2"}
    ).json()
    secrets = _register(client, admin_token, hive_id=hive["id"])
    event = _signed(
        client,
        secrets,
        {"temperature_c": 33.0, "humidity_percent": 60.0, "hive_weight_kg": 22.5},
    )
    resp = client.post(f"/api/v1/iot/devices/{secrets['device_id']}/telemetry", json=event)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["accepted"] is True
    assert body["sequence"] == 1
    assert body["hive_id"] == hive["id"]
    assert body["alert_triggered"] is False

    readings = client.get(
        f"/api/v1/hives/{hive['id']}/readings", headers=auth(demo_token)
    ).json()
    assert len(readings) == 1
    assert readings[0]["source"] == "simulation"

    # Committed as a real event
    events = client.get(
        f"/api/v1/iot/devices/{secrets['device_id']}/telemetry",
        headers=auth(demo_token),
    ).json()
    assert len(events) == 1
    assert events[0]["sequence"] == 1


def test_ingest_rejects_duplicate_event(client, admin_token):
    secrets = _register(client, admin_token)
    event = _signed(client, secrets, {"temperature_c": 30.0})
    url = f"/api/v1/iot/devices/{secrets['device_id']}/telemetry"
    assert client.post(url, json=event).status_code == 200
    dup = client.post(url, json=event)
    assert dup.status_code == 400
    assert "duplicate" in dup.json()["detail"].lower()


def test_ingest_rejects_sequence_gap(client, admin_token):
    secrets = _register(client, admin_token)
    # First event is sequence 5 — a gap from expected=1
    event = _signed(client, secrets, {"temperature_c": 31.0}, sequence=5)
    resp = client.post(f"/api/v1/iot/devices/{secrets['device_id']}/telemetry", json=event)
    assert resp.status_code == 400
    assert "gap" in resp.json()["detail"].lower()


def test_ingest_rejects_invalid_signature(client, admin_token):
    secrets = _register(client, admin_token)
    event = _signed(client, secrets, {"temperature_c": 32.0})
    # Tamper with the payload, re-hash, keep the STALE signature
    event["payload"] = {"temperature_c": 42.0}
    event["payload_hash"] = hash_payload_json(event["payload"])
    resp = client.post(f"/api/v1/iot/devices/{secrets['device_id']}/telemetry", json=event)
    assert resp.status_code == 400
    assert "signature" in resp.json()["detail"].lower()


def test_ingest_rejects_payload_hash_mismatch(client, admin_token):
    secrets = _register(client, admin_token)
    event = _signed(client, secrets, {"temperature_c": 32.0})
    event["payload_hash"] = "0" * 64
    resp = client.post(f"/api/v1/iot/devices/{secrets['device_id']}/telemetry", json=event)
    assert resp.status_code == 400
    assert "payload_hash" in resp.json()["detail"].lower()


def test_batch_rejects_replayed_events(client, admin_token):
    secrets = _register(client, admin_token)
    events = [_signed(client, secrets, {"temperature_c": 30.0}, sequence=n, timestamp=f"2026-09-09T09:{n:02d}:00+00:00") for n in (1, 2, 3)]
    url = f"/api/v1/iot/devices/{secrets['device_id']}/telemetry/batch"
    first = client.post(url, json={"events": events})
    assert first.json()["rejected"] == []
    # Replaying the identical offline queue: every event is a duplicate
    replay = client.post(url, json={"events": events})
    body = replay.json()
    assert len(body["accepted"]) == 0
    assert len(body["rejected"]) == 3


# ----------------------------------------------------- simulator + offline


def test_simulator_offline_recovery_cycle(client, admin_token):
    secrets = _register(client, admin_token)
    did = secrets["device_id"]

    resp = client.post(
        "/api/v1/iot/simulator/mode", headers=auth(admin_token), json={"device_id": did, "mode": "OFFLINE"}
    )
    assert resp.status_code == 200

    for _ in range(3):
        step = client.post(
            "/api/v1/iot/simulator/control",
            headers=auth(admin_token),
            json={"action": "STEP", "device_id": did},
        ).json()
        assert step["event"].get("queued") is True

    status = client.get("/api/v1/iot/simulator/status", headers=auth(admin_token)).json()
    mine = next(d for d in status if d["device_id"] == did)
    assert mine["device_status"] == "OFFLINE"
    assert mine["pending_events"] == 3

    # Recovery flushes the queue through the real ingestion path
    resp = client.post(
        "/api/v1/iot/simulator/mode", headers=auth(admin_token), json={"device_id": did, "mode": "RECOVERY"}
    )
    assert resp.status_code == 200
    assert resp.json()["device_status"] == "ONLINE"

    status = client.get("/api/v1/iot/simulator/status", headers=auth(admin_token)).json()
    mine = next(d for d in status if d["device_id"] == did)
    assert mine["pending_events"] == 0

    events = client.get(
        f"/api/v1/iot/devices/{did}/telemetry", headers=auth(admin_token)
    ).json()
    assert len(events) == 3


def test_simulator_burst_generates_events(client, admin_token):
    secrets = _register(client, admin_token)
    resp = client.post(
        "/api/v1/iot/simulator/control",
        headers=auth(admin_token),
        json={"action": "GENERATE_EVENT", "device_id": secrets["device_id"], "burst_count": 5},
    )
    assert resp.status_code == 200
    assert resp.json()["count"] == 5


def test_simulator_fork_conflict(client, admin_token):
    secrets = _register(client, admin_token)
    resp = client.post(
        "/api/v1/iot/simulator/fork",
        headers=auth(admin_token),
        json={"device_id": secrets["device_id"]},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["conflict"]["detected"] is True
    assert len(body["conflict"]["heads"]) == 2
    assert body["conflict"]["branch_a_hash"] != body["conflict"]["branch_b_hash"]
    assert body["integrity_ok"] is True


def test_simulator_control_forbidden_for_beekeeper(client, demo_token):
    resp = client.post(
        "/api/v1/iot/simulator/control",
        headers=auth(demo_token),
        json={"action": "START", "device_id": "HC-SIM-x"},
    )
    assert resp.status_code == 403

    resp = client.get("/api/v1/iot/simulator/status", headers=auth(demo_token))
    assert resp.status_code == 403