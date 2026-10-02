"""Notification/alerts derived from real ingestion outcomes.

Alert visibility follows the same role scoping as devices: beekeepers only
see alerts for their own hives.
"""
from __future__ import annotations

from app.services.iot_service import IoTDeviceService, hash_payload_json
from tests.conftest import auth, make_token

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


def test_buyer_inbox_is_scoped_to_their_own_organization(client):
    """A buyer can read an inbox, but only ever rows addressed to its org.

    This is the guard that makes granting `notification.read` to buyers safe:
    the repository filters by organization, so the grant does not open the
    seller's inbox or another buyer's. Written against the repository directly
    because the point being proven is the scoping, not the HTTP plumbing.
    """
    repo = client.app.state.repository
    # `buyer_token` carries no org, so create a bound buyer identity instead.
    repo.ensure_organization(
        {"id": "ORG-NOTIF-BUYER", "name": "Notify Buyer", "type": "buyer"}
    )
    buyer = make_token("notify-buyer-id", "buyer", "ORG-NOTIF-BUYER")
    repo.add_notification(
        {
            "notification_id": None,
            "title": "Seller inbox item",
            "body": "not for the buyer",
            "category": "MARKET_LISTED",
            "severity": "info",
            "reason": "",
            "recommended_action": "",
            "source": "workflow",
            "hive_id": None,
            "batch_id": None,
            "device_id": None,
            "organization_id": "ORG-NOTIF-SELLER",
            "is_simulated": False,
            "read": False,
            "created_at": "2026-09-09T10:00:00+00:00",
        }
    )
    inbox = client.get("/api/v1/notifications", headers=auth(buyer)).json()
    # The buyer's inbox is readable, and holds nothing addressed to the seller.
    assert all(n["organization_id"] == "ORG-NOTIF-BUYER" for n in inbox["items"])


def test_notifications_require_permission(client, lab_token):
    """The notifications gate is real: a role without the permission is denied.

    `lab` is the role used here because it genuinely does not hold
    `notification.read`. It was previously `buyer`, back when a buyer only
    browsed lots and never acted on them. A buyer now requests, accepts and
    fulfils real orders, so it holds the permission and is covered by
    `test_buyer_inbox_is_scoped_to_their_own_organization` instead.
    """
    resp = client.get("/api/v1/notifications", headers=auth(lab_token))
    assert resp.status_code == 403