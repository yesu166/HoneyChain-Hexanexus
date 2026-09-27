"""Cross-tenant (FPO) isolation regression tests.

These pin the HC-3.0 contract that org-bound callers may never read or mutate
another organization's supply-chain data through any route or the sync API.
"""
from __future__ import annotations

from tests.conftest import auth, make_token

ORG_A = "ORG-TN-001"
ORG_B = "ORG-TN-002"


def _fpo_b_token():
    return make_token("fpo-user-b", "fpo", ORG_B)


def _seed_batch(client, token, code="HC-ISO-1", qty=6.0):
    hive = client.post(
        "/api/v1/hives", headers=auth(token), json={"hive_code": "HIVE-ISO"}
    ).json()
    harvest = client.post(
        "/api/v1/harvests",
        headers=auth(token),
        json={"hive_id": hive["id"], "quantity_kg": qty},
    ).json()
    return client.post(
        "/api/v1/batches",
        headers=auth(token),
        json={
            "batch_code": code,
            "quantity_kg": qty,
            "harvest_ids": [harvest["id"]],
            "organization_id": ORG_A,
        },
    ).json()


# ------------------------------------------------------------------ read scope
def test_fpo_cannot_read_foreign_batch(client, fpo_token):
    batch = _seed_batch(client, fpo_token)
    resp = client.get(f"/api/v1/batches/{batch['id']}", headers=auth(_fpo_b_token()))
    assert resp.status_code == 404
    listed = client.get("/api/v1/batches", headers=auth(_fpo_b_token())).json()
    assert batch["id"] not in [b["id"] for b in listed]


def test_fpo_cannot_list_foreign_batches(client, fpo_token):
    _seed_batch(client, fpo_token)
    other = _fpo_b_token()
    assert client.get("/api/v1/batches", headers=auth(other)).json() == []


def test_processor_is_org_scoped(client, fpo_token, processor_token):
    batch = _seed_batch(client, fpo_token)
    other_proc = make_token("proc-user-b", "processor", ORG_B)
    assert (
        client.get(f"/api/v1/batches/{batch['id']}", headers=auth(other_proc)).status_code
        == 404
    )
    # Same-org processor sees the batch (matrix scope read_org).
    owner_proc = make_token("proc-user-a", "processor", ORG_A)
    assert (
        client.get(f"/api/v1/batches/{batch['id']}", headers=auth(owner_proc)).status_code
        == 200
    )


# ------------------------------------------------------------------ mutate scope
def test_fpo_cannot_split_foreign_batch(client, fpo_token):
    batch = _seed_batch(client, fpo_token, "HC-ISO-SPLIT")
    resp = client.post(
        f"/api/v1/batches/{batch['id']}/split",
        headers=auth(_fpo_b_token()),
        json={"child_quantities_kg": [3.0, 3.0]},
    )
    assert resp.status_code == 409
    assert "not in your scope" in resp.json()["detail"]


def test_fpo_cannot_merge_foreign_batch(client, fpo_token):
    a = _seed_batch(client, fpo_token, "HC-ISO-MA")
    b = _seed_batch(client, fpo_token, "HC-ISO-MB")
    resp = client.post(
        "/api/v1/batches/merge",
        headers=auth(_fpo_b_token()),
        json={"batch_ids": [a["id"], b["id"]], "new_batch_code": "HC-ISO-MG"},
    )
    assert resp.status_code == 409
    assert "not in your scope" in resp.json()["detail"]


def test_fpo_cannot_transition_foreign_batch(client, fpo_token):
    batch = _seed_batch(client, fpo_token, "HC-ISO-TR")
    resp = client.post(
        "/api/v1/batches/transition",
        headers=auth(_fpo_b_token()),
        json={"batch_id": batch["id"], "to_state": "processing"},
    )
    assert resp.status_code == 403


# ------------------------------------------------------------------ create scope
def test_batch_create_forces_server_org(client, fpo_token):
    # An org-bound caller may never stamp another org's id onto a batch it owns.
    created = client.post(
        "/api/v1/batches",
        headers=auth(_fpo_b_token()),
        json={
            "batch_code": "HC-ISO-SPOOF",
            "quantity_kg": 5.0,
            "organization_id": ORG_A,
        },
    )
    assert created.status_code == 201
    assert created.json()["organization_id"] == ORG_B
    # ORG-A cannot see the spoofed-looking batch.
    assert (
        client.get(
            f"/api/v1/batches/{created.json()['id']}", headers=auth(fpo_token)
        ).status_code
        == 404
    )


# ------------------------------------------------------------------ sync scope
def test_sync_push_batch_uses_caller_org(client, fpo_token):
    push = client.post(
        "/api/v1/sync/push",
        headers=auth(_fpo_b_token()),
        json={
            "items": [
                {
                    "entity": "batch",
                    "client_id": "iso-sync-b",
                    "data": {"batch_code": "HC-ISO-SYNCB", "quantity_kg": 4.0},
                }
            ]
        },
    )
    assert push.status_code == 200
    accepted = push.json()["accepted"]
    assert accepted and accepted[0]["accepted"] is True
    backend_id = accepted[0]["backend_id"]
    row = client.get(
        f"/api/v1/batches/{backend_id}", headers=auth(_fpo_b_token())
    ).json()
    assert row["organization_id"] == ORG_B
    # ORG-A must not see it through sync or direct read.
    assert (
        client.get(f"/api/v1/batches/{backend_id}", headers=auth(fpo_token)).status_code
        == 404
    )


def test_sync_push_custody_foreign_batch_rejected(client, fpo_token):
    batch = _seed_batch(client, fpo_token, "HC-ISO-CUST")
    push = client.post(
        "/api/v1/sync/push",
        headers=auth(_fpo_b_token()),
        json={
            "items": [
                {
                    "entity": "custody",
                    "client_id": "iso-cust-1",
                    "data": {"batch_id": batch["id"], "action": "COLLECTION"},
                }
            ]
        },
    )
    body = push.json()
    assert body["rejected"]
    assert "not in your scope" in body["rejected"][0]["error"]


def test_sync_push_requires_permission(client, lab_token):
    # lab role has no sync.push permission.
    resp = client.post("/api/v1/sync/push", json={"items": []}, headers=auth(lab_token))
    assert resp.status_code == 403


# ------------------------------------------------------------------ notifications
def test_fpo_cannot_mark_foreign_notification_read(client, demo_token, admin_token):
    hive = client.post(
        "/api/v1/hives", headers=auth(demo_token), json={"hive_code": "HIVE-ISO-NOTIF"}
    ).json()
    resp = client.post(
        "/api/v1/iot/devices",
        headers=auth(admin_token),
        json={
            "device_name": "HC-SIM-ISO",
            "device_type": "hive-sensor",
            "firmware_version": "1.0.0",
            "assigned_hive_id": hive["id"],
            "organization_id": ORG_A,
        },
    )
    device = resp.json()
    from app.services.iot_service import IoTDeviceService

    event = IoTDeviceService.signed_event(
        {
            "event_id": f"{device['device_id']}-1",
            "device_id": device["device_id"],
            "sequence": 1,
            "timestamp": "2026-09-09T10:00:00+00:00",
            "payload": {"temperature_c": 40.0},
        },
        device["device_private_key_pem"],
    )
    client.post(f"/api/v1/iot/devices/{device['device_id']}/telemetry", json=event)

    notes = client.get("/api/v1/notifications", headers=auth(demo_token)).json()
    note = notes["items"][0]

    denied = client.post(
        f"/api/v1/notifications/{note['notification_id']}/read",
        headers=auth(_fpo_b_token()),
    )
    assert denied.status_code == 403


# ------------------------------------------------------------------ auth hardening
def test_register_cannot_create_admin(client):
    resp = client.post(
        "/api/v1/auth/register",
        json={
            "email": "sneaky-admin@honeychain.in",
            "name": "Sneaky",
            "password": "StrongPass123",
            "role": "admin",
        },
    )
    assert resp.status_code == 422


def test_register_beekeeper_gets_producer_id(client):
    resp = client.post(
        "/api/v1/auth/register",
        json={
            "email": "producer-new@honeychain.in",
            "name": "New Beekeeper",
            "phone": "+919222222222",
            "password": "StrongPass123",
            "role": "beekeeper",
            "org_id": ORG_A,
        },
    )
    assert resp.status_code == 201
    assert resp.json()["producer_id"].startswith("HC-BK-")
    login = client.post(
        "/api/v1/auth/login",
        json={"identifier": "producer-new@honeychain.in", "password": "StrongPass123"},
    ).json()
    me = client.get("/api/v1/auth/me", headers=auth(login["access_token"])).json()
    assert me["producer_id"] == resp.json()["producer_id"]


def test_register_fpo_requires_org(client):
    resp = client.post(
        "/api/v1/auth/register",
        json={
            "email": "orgless-fpo@honeychain.in",
            "name": "No Org",
            "password": "StrongPass123",
            "role": "fpo",
        },
    )
    assert resp.status_code == 409


# ------------------------------------------------------------------ org dashboard
def test_org_dashboard_is_zero_based_and_scoped(client, fpo_token):
    # The seeded demo beekeeper lives in the generic demo org key.
    demo_org = "ORG-000001"
    demo_scope = auth(make_token("fpo-demo-org", "fpo", demo_org))
    dashboard = client.get(f"/api/v1/org/{demo_org}/dashboard", headers=demo_scope)
    assert dashboard.status_code == 200
    body = dashboard.json()
    assert body["org_id"] == demo_org
    assert body["source"] == "backend"
    assert body["active_beekeepers"] >= 1  # seeded demo beekeeper is real + counted
    assert body["batches"] == 0
    assert body["recent_activity"] == []

    # A caller from another org cannot read it.
    denied = client.get(
        f"/api/v1/org/{demo_org}/dashboard", headers=auth(_fpo_b_token())
    )
    assert denied.status_code == 403


def test_org_dashboard_accepts_uuid_and_public_org_key_for_same_fpo(client, fpo_token):
    org = client.app.state.repository.get_organization(ORG_A)
    assert org is not None
    org_uuid = str(org.get("id") or "")
    assert org_uuid

    by_key = client.get(f"/api/v1/org/{ORG_A}/dashboard", headers=auth(fpo_token))
    by_uuid = client.get(f"/api/v1/org/{org_uuid}/dashboard", headers=auth(fpo_token))
    assert by_key.status_code == 200
    assert by_uuid.status_code == 200
    assert by_key.json()["org_id"] == ORG_A
    assert by_uuid.json()["org_id"] == org_uuid
    assert by_key.json()["batches"] == by_uuid.json()["batches"]


def test_org_dashboard_tracks_created_batch(client, fpo_token):
    batch = _seed_batch(client, fpo_token, "HC-ISO-DASH")
    body = client.get(
        f"/api/v1/org/{ORG_A}/dashboard", headers=auth(fpo_token)
    ).json()
    assert body["batches"] == 1
    assert body["verified_batches"] == 0
    assert any(
        item["entity_ref"] == batch["id"] for item in body["recent_activity"]
    )


def test_platform_stats_privileged(client, admin_token, fpo_token):
    stats = client.get("/api/v1/platform/stats", headers=auth(admin_token))
    assert stats.status_code == 200
    assert stats.json()["organizations"] >= 1
    # org-bound roles must not see platform aggregates.
    assert (
        client.get("/api/v1/platform/stats", headers=auth(fpo_token)).status_code
        == 403
    )