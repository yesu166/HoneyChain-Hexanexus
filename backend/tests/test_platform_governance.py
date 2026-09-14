from __future__ import annotations

import re

from tests.conftest import auth, make_token


def _platform_token() -> str:
    return make_token("platform-user-id", "platform_oversight")


def _fpo_token() -> str:
    return make_token("u-fpo", "fpo", "ORG-TN-001")


def _institution_token() -> str:
    return make_token("institution-user-id", "institution")


def _admin_token() -> str:
    return make_token("u-admin", "admin")


def _create_fpo(client, token: str, name: str = "Palani Hills Honey FPO") -> dict:
    resp = client.post(
        "/api/v1/platform/organizations", json={"name": name}, headers=auth(token)
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def _register_beekeeper(client, email: str, phone: str) -> dict:
    resp = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "name": "Kumar Beekeeper",
            "phone": phone,
            "password": "Str0ngPass!42",
            "role": "beekeeper",
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


# ---------------------------------------------------------------- authz matrix
def test_admin_denied_all_membership_actions_at_route_level(client):
    org_key = _create_fpo(client, _platform_token())["organization_key"]
    admin = auth(_admin_token())
    members = [
        ("assign", lambda: client.post(
            f"/api/v1/platform/organizations/{org_key}/beekeepers",
            json={"user_id": "some-user"},
            headers=admin,
        )),
        ("revoke", lambda: client.post(
            f"/api/v1/platform/organizations/{org_key}/members/some-user/revoke",
            headers=admin,
        )),
        ("suspend", lambda: client.post(
            f"/api/v1/platform/organizations/{org_key}/members/some-user/suspend",
            headers=admin,
        )),
        ("reinstate", lambda: client.post(
            f"/api/v1/platform/organizations/{org_key}/members/some-user/reinstate",
            headers=admin,
        )),
        ("view members", lambda: client.get(
            f"/api/v1/platform/organizations/{org_key}/members", headers=admin
        )),
        ("deactivate", lambda: client.post(
            f"/api/v1/platform/organizations/{org_key}/deactivate", headers=admin
        )),
    ]
    for label, call in members:
        assert call().status_code == 403, f"admin must be denied {label}"


def test_non_oversight_roles_denied_membership_view(client, fpo_token):
    for label in ("membership list", "platform beekeepers"):
        headers = auth(fpo_token) if label == "membership list" else auth(fpo_token)
        url = (
            "/api/v1/platform/organizations/ORG-TN-001/members"
            if label == "membership list"
            else "/api/v1/platform/beekeepers"
        )
        assert client.get(url, headers=headers).status_code in (403, 404)


def test_platform_oversight_cannot_create_domain_data(client):
    platform = auth(_platform_token())
    assert (
        client.post("/api/v1/batches", json={"batch_code": "HC-X", "quantity_kg": 1.0}, headers=platform).status_code
        == 403
    )


# ---------------------------------------------------------------- lifecycle
def test_deactivate_reqires_oversight_and_then_activates(client):
    token = _platform_token()
    org_key = _create_fpo(client, token)["organization_key"]
    # suspended state transitions
    deactivate = client.post(
        f"/api/v1/platform/organizations/{org_key}/deactivate", headers=auth(token)
    )
    assert deactivate.status_code == 200
    assert deactivate.json()["status"] == "DORMANT"
    activate = client.post(
        f"/api/v1/platform/organizations/{org_key}/activate", headers=auth(token)
    )
    assert activate.status_code == 200
    assert activate.json()["status"] == "ACTIVE"


# ---------------------------------------------------------------- invitation revoke
def test_revoked_admin_invite_cannot_register(client):
    token = _platform_token()
    org_key = _create_fpo(client, token)["organization_key"]
    invite = client.post(
        f"/api/v1/platform/organizations/{org_key}/admins",
        json={"email": "adminx@palani.example"},
        headers=auth(token),
    ).json()
    revoke = client.post(
        f"/api/v1/platform/organizations/{org_key}/admins/{invite['id']}/revoke",
        headers=auth(token),
    )
    assert revoke.status_code == 200
    assert revoke.json()["status"] == "REVOKED"
    bad_register = client.post(
        "/api/v1/auth/register",
        json={
            "email": "adminx@palani.example",
            "name": "Admin X",
            "phone": "+919000000060",
            "password": "Str0ngPass!42",
            "role": "fpo",
            "invite_code": invite["token"],
        },
    )
    assert bad_register.status_code == 409


# ---------------------------------------------------------------- membership
def test_assign_beekeeper_binds_org_and_preserves_producer_id(client):
    token = _platform_token()
    org_key = _create_fpo(client, token)["organization_key"]
    me = _register_beekeeper(client, "bkassign@example.in", "+919000000061")
    assert me["producer_id"].startswith("HC-BK-")
    assert me["org_id"] == ""

    assign = client.post(
        f"/api/v1/platform/organizations/{org_key}/beekeepers",
        json={"user_id": me["id"]},
        headers=auth(token),
    )
    assert assign.status_code == 200
    assert assign.json()["org_id"] == org_key

    refreshed = client.get("/api/v1/auth/me", headers=auth(make_token(me["id"], "beekeeper"))).json()
    assert refreshed["org_id"] == org_key
    assert refreshed["producer_id"] == me["producer_id"]
    assert refreshed["org_name"] == "Palani Hills Honey FPO"

    members = client.get(
        f"/api/v1/platform/organizations/{org_key}/members", headers=auth(token)
    ).json()
    assert any(m["id"] == me["id"] for m in members)


def test_revoke_membership_preserves_history_and_producer_id(client):
    token = _platform_token()
    org_key = _create_fpo(client, token)["organization_key"]
    me = _register_beekeeper(client, "bkrevoke@example.in", "+919000000062")
    producer_id = me["producer_id"]
    client.post(
        f"/api/v1/platform/organizations/{org_key}/beekeepers",
        json={"user_id": me["id"]},
        headers=auth(token),
    )
    # Beekeeper creates supply-chain history while a member.
    hive = client.post(
        "/api/v1/hives",
        json={"hive_code": "HIVE-GOV"},
        headers=auth(make_token(me["id"], "beekeeper", org_key)),
    )
    assert hive.status_code == 201

    revoke = client.post(
        f"/api/v1/platform/organizations/{org_key}/members/{me['id']}/revoke",
        headers=auth(token),
    )
    assert revoke.status_code == 200
    assert revoke.json()["org_id"] == ""

    refreshed = client.get("/api/v1/auth/me", headers=auth(make_token(me["id"], "beekeeper", ""))).json()
    assert refreshed["org_id"] == ""
    assert refreshed["producer_id"] == producer_id  # Producer ID persists

    # Historical records remain intact and still belong to the beekeeper.
    hives = client.get(
        "/api/v1/hives",
        headers=auth(make_token(me["id"], "beekeeper", "")),
    )
    assert hives.status_code == 200
    assert any(h["id"] == hive.json()["id"] for h in hives.json())


def test_assign_revokes_membership_strictly_scoped(client):
    token = _platform_token()
    org_key = _create_fpo(client, token)["organization_key"]
    me = _register_beekeeper(client, "bkscope@example.in", "+919000000063")
    # Revoking a non-member must fail cleanly with 404.
    revoke = client.post(
        f"/api/v1/platform/organizations/{org_key}/members/{me['id']}/revoke",
        headers=auth(token),
    )
    assert revoke.status_code == 404


def test_suspend_and_reinstate_member_blocks_account_and_audits(client):
    token = _platform_token()
    org_key = _create_fpo(client, token)["organization_key"]
    me = _register_beekeeper(client, "bksuspend@example.in", "+919000000064")
    client.post(
        f"/api/v1/platform/organizations/{org_key}/beekeepers",
        json={"user_id": me["id"]},
        headers=auth(token),
    )
    beekeeper_auth = auth(make_token(me["id"], "beekeeper", org_key))
    assert client.get("/api/v1/auth/me", headers=beekeeper_auth).status_code == 200

    suspend = client.post(
        f"/api/v1/platform/organizations/{org_key}/members/{me['id']}/suspend",
        headers=auth(token),
    )
    assert suspend.status_code == 200
    assert suspend.json()["status"] == "SUSPENDED"

    # Suspended account: existing tokens rejected on authz, login rejected.
    assert client.get("/api/v1/auth/me", headers=beekeeper_auth).status_code == 403
    blocked = client.post(
        "/api/v1/auth/login",
        json={"identifier": "bksuspend@example.in", "password": "Str0ngPass!42"},
    )
    assert blocked.status_code == 401

    reinstate = client.post(
        f"/api/v1/platform/organizations/{org_key}/members/{me['id']}/reinstate",
        headers=auth(token),
    )
    assert reinstate.status_code == 200
    assert reinstate.json()["status"] == "ACTIVE"
    assert client.get("/api/v1/auth/me", headers=beekeeper_auth).status_code == 200


# ---------------------------------------------------------------- visibility
def test_platform_wide_beekeeper_and_member_visibility(client):
    token = _platform_token()
    org_key = _create_fpo(client, token)["organization_key"]
    me = _register_beekeeper(client, "bkview@example.in", "+919000000065")
    client.post(
        f"/api/v1/platform/organizations/{org_key}/beekeepers",
        json={"user_id": me["id"]},
        headers=auth(token),
    )
    all_bees = client.get("/api/v1/platform/beekeepers", headers=auth(token))
    assert all_bees.status_code == 200
    assert any(
        b["id"] == me["id"]
        and b["producer_id"] == me["producer_id"]
        and b["org_key"] == org_key
        for b in all_bees.json()
    )
    scoped = client.get(
        f"/api/v1/platform/beekeepers?org_key={org_key}", headers=auth(token)
    ).json()
    assert any(b["id"] == me["id"] for b in scoped)
    members = client.get(
        f"/api/v1/platform/organizations/{org_key}/members", headers=auth(token)
    ).json()
    assert any(m["id"] == me["id"] and m["status"] == "ACTIVE" for m in members)


# ---------------------------------------------------------------- audit
def test_sensitive_actions_are_attributed_in_audit(client):
    token = _platform_token()
    org_key = _create_fpo(client, token)["organization_key"]
    client.post(
        f"/api/v1/platform/organizations/{org_key}/suspend", headers=auth(token)
    )
    me = _register_beekeeper(client, "bkaudit@example.in", "+919000000066")
    client.post(
        f"/api/v1/platform/organizations/{org_key}/beekeepers",
        json={"user_id": me["id"]},
        headers=auth(token),
    )

    audit = client.get("/api/v1/platform/audit", headers=auth(token)).json()
    actions = [a["action"] for a in audit]
    for expected in ("organization.create", "organization.suspend", "membership.assign"):
        assert expected in actions, f"missing audit entry {expected}"
    assert all(a["actor_user_id"] == "platform-user-id" for a in audit)
    assert all(a["actor_role"] == "platform_oversight" for a in audit)


def test_audit_visible_to_admin_and_institution_but_not_fpo(client):
    token = _platform_token()
    _create_fpo(client, token)
    assert client.get("/api/v1/platform/audit", headers=auth(_admin_token())).status_code == 200
    assert (
        client.get("/api/v1/platform/audit", headers=auth(_institution_token())).status_code
        == 200
    )
    assert client.get("/api/v1/platform/audit", headers=auth(_fpo_token())).status_code == 403


# ---------------------------------------------------------------- identity neutralization
def test_no_state_specific_default_identities_in_schemas():
    from app.schemas.certificate import CertificateIssue
    from app.schemas.lab import LabTestCreate

    assert not re.search(r"TN-00\d|KA-|Nilgiris|ORG-[A-Z]{2}[-_]", LabTestCreate(batch_id="x").lab_id)
    assert not re.search(r"TN-00\d|KA-|Nilgiris|ORG-[A-Z]{2}[-_]", CertificateIssue(batch_id="x").lab_id)