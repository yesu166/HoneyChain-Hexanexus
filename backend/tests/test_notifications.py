"""Notification/alerts derived from real ingestion outcomes.

Alert visibility follows the same role scoping as devices: beekeepers only
see alerts for their own hives.
"""
from __future__ import annotations

from app.services.iot_service import IoTDeviceService, hash_payload_json
from tests.conftest import auth

TS = "2026-09-09T10:00:00+00:00"


def _register_and_send(client, admin_token, hive_id, payload):
    resp = client.post(
        "/api/v1/iot/devices",
        headers=auth(admin_token),
        json={
            "device_name": "HC-SIM-HIVE-001",
            "device_type": "hive-sensor",
            "firmware_version": "1.3.0",
            "assigned_hive_id": hive_id or None,
            "organization_id": "ORG-TN-001",
        },
    )
    secrets = resp.json()
    event = {
        "event_id": f"{secrets['device_id']}-1",
        "device_id": secrets["device_id"],
        "sequence": 1,
        "timestamp": TS,
        "payload": payload,
    }
    event = IoTDeviceService.signed_event(event, secrets["device_private_key_pem"])
    out = client.post(
        f"/api/v1/iot/devices/{secrets['device_id']}/telemetry", json=event
    )
    assert out.status_code == 200, out.text
    return secrets, out.json()


def test_high_temperature_raises_alert(client, demo_token, admin_token):
    hive = client.post(
        "/api/v1/hives", headers=auth(demo_token), json={"hive_code": "HIVE-AL1"}
    ).json()
    _, body = _register_and_send(
        client,
        admin_token,
        hive["id"],
        {"temperature_c": 40.0, "humidity_percent": 55.0},
    )
    assert body["alert_triggered"] is True

    notes = client.get("/api/v1/notifications", headers=auth(demo_token)).json()
    assert notes["unread_count"] >= 1
    assert any(n["reason"] == "High temperature" for n in notes["items"])
    high = next(n for n in notes["items"] if n["reason"] == "High temperature")
    assert high["hive_id"] == hive["id"]
    assert high["severity"] == "warning"
    assert high["source"] == "iot"
    assert high["is_simulated"] is True


def test_rapid_weight_loss_is_critical(client, demo_token, admin_token):
    hive = client.post(
        "/api/v1/hives", headers=auth(demo_token), json={"hive_code": "HIVE-AL2"}
    ).json()
    resp = client.post(
        "/api/v1/iot/devices",
        headers=auth(admin_token),
        json={
            "device_name": "HC-SIM-WL",
            "device_type": "hive-sensor",
            "firmware_version": "1.0.0",
            "assigned_hive_id": hive["id"],
            "organization_id": "ORG-TN-001",
        },
    )
    secrets = resp.json()
    for i, ts in enumerate(["2026-09-09T08:00:00+00:00", "2026-09-09T08:05:00+00:00"]):
        weight = 22.0 if i == 0 else 16.0  # -27% between readings
        event = {
            "event_id": f"{secrets['device_id']}-{i + 1}",
            "device_id": secrets["device_id"],
            "sequence": i + 1,
            "timestamp": ts,
            "payload": {
                "temperature_c": 26.0,
                "humidity_percent": 60.0,
                "hive_weight_kg": weight,
            },
        }
        event = IoTDeviceService.signed_event(event, secrets["device_private_key_pem"])
        out = client.post(
            f"/api/v1/iot/devices/{secrets['device_id']}/telemetry", json=event
        )
        assert out.status_code == 200, out.text

    notes = client.get("/api/v1/notifications", headers=auth(demo_token)).json()
    assert any(n["reason"] == "Rapid weight loss" for n in notes["items"])
    wl = next(n for n in notes["items"] if n["reason"] == "Rapid weight loss")
    assert wl["severity"] == "critical"


def test_sequence_rejection_raises_integrity_alert(client, demo_token, admin_token):
    hive = client.post(
        "/api/v1/hives", headers=auth(demo_token), json={"hive_code": "HIVE-AL3"}
    ).json()
    resp = client.post(
        "/api/v1/iot/devices",
        headers=auth(admin_token),
        json={
            "device_name": "HC-SIM-GAP",
            "device_type": "hive-sensor",
            "firmware_version": "1.0.0",
            "assigned_hive_id": hive["id"],
            "organization_id": "ORG-TN-001",
        },
    )
    did = resp.json()["device_id"]
    # Valid payload hash but jumping ahead to sequence 5 -> stopped at the
    # sequence gate (before signature validation).
    payload = {"temperature_c": 25.0}
    out = client.post(
        f"/api/v1/iot/devices/{did}/telemetry",
        json={
            "event_id": f"{did}-5",
            "device_id": did,
            "sequence": 5,
            "timestamp": TS,
            "payload": payload,
            "payload_hash": hash_payload_json(payload),
            "signature": "",
        },
    )
    assert out.status_code == 400

    notes = client.get("/api/v1/notifications", headers=auth(demo_token)).json()
    assert any(n["reason"] == "Sequence gap" for n in notes["items"])


def test_mark_read(client, demo_token, admin_token):
    hive = client.post(
        "/api/v1/hives", headers=auth(demo_token), json={"hive_code": "HIVE-AL4"}
    ).json()
    _, body = _register_and_send(
        client,
        admin_token,
        hive["id"],
        {"temperature_c": 39.5, "humidity_percent": 55.0},
    )
    assert body["alert_triggered"] is True

    notes = client.get("/api/v1/notifications", headers=auth(demo_token)).json()
    note = notes["items"][0]
    assert note["read"] is False

    resp = client.post(
        f"/api/v1/notifications/{note['notification_id']}/read",
        headers=auth(demo_token),
    )
    assert resp.json()["read"] is True

    again = client.get("/api/v1/notifications", headers=auth(demo_token)).json()
    assert again["unread_count"] == notes["unread_count"] - 1


def test_beekeeper_only_sees_own_hive_alerts(client, demo_token, fpo_token, admin_token):
    other_hive = client.post(
        "/api/v1/hives", headers=auth(demo_token), json={"hive_code": "HIVE-AL5"}
    ).json()
    _, _ = _register_and_send(
        client,
        admin_token,
        other_hive["id"],
        {"temperature_c": 41.0, "humidity_percent": 55.0},
    )
    # FPO sees raw alert data scoped to org
    fpo_notes = client.get("/api/v1/notifications", headers=auth(fpo_token)).json()
    assert any(n["hive_id"] == other_hive["id"] for n in fpo_notes["items"])


def test_notifications_require_permission(client, buyer_token):
    resp = client.get("/api/v1/notifications", headers=auth(buyer_token))
    assert resp.status_code == 403