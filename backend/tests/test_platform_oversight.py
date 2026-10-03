from __future__ import annotations

import re

from tests.conftest import auth, make_token


def _platform_token() -> str:
    return make_token("platform-user-id", "platform_oversight")


def _institution_token() -> str:
    return make_token("institution-user-id", "institution")


def _create_fpo(client, token: str, **overrides) -> dict:
    payload = {"name": "Palani Hills Honey FPO"}
    payload.update(overrides)
    return client.post(
        "/api/v1/platform/organizations", json=payload, headers=auth(token)
    )


def test_platform_oversight_creates_fpo_with_server_key(client):
    resp = _create_fpo(client, _platform_token())
    assert resp.status_code == 201
    body = resp.json()
    assert re.fullmatch(r"ORG-\d{6}", body["organization_key"])
    assert body["status"] == "PENDING"
    assert body["name"] == "Palani Hills Honey FPO"
    assert len(body["id"]) == 36


def test_organization_keys_are_unique(client):
    token = _platform_token()
    a = _create_fpo(client, token).json()["organization_key"]
    b = _create_fpo(client, token).json()["organization_key"]
    assert a != b


def test_every_non_oversight_role_rejected_for_org_create(client):
    """Admin may create organizations; every other non-oversight role may not."""
    allowed = {"admin": make_token("u-admin", "admin")}
    denied = {
        "beekeeper": make_token("u-beekeeper", "beekeeper", "ORG-TN-001"),
        "fpo": make_token("u-fpo", "fpo", "ORG-TN-001"),
        "lab": make_token("u-lab", "lab", "LAB-TN-001"),
        "processor": make_token("u-proc", "processor"),
        "buyer": make_token("u-buyer", "buyer"),
        "institution": _institution_token(),
    }
    for role, token in allowed.items():
        resp = _create_fpo(client, token)
        assert resp.status_code == 201, f"{role} must be able to create organizations"
    for role, token in denied.items():
        resp = _create_fpo(client, token)
        assert resp.status_code == 403, f"{role} must not create organizations"


def test_non_oversight_roles_cannot_activate_suspend_or_onboard(client):
    token = _platform_token()
    org_key = _create_fpo(client, token).json()["organization_key"]
    fpo = auth(make_token("u-fpo", "fpo", "ORG-TN-001"))
    lab = auth(make_token("u-lab", "lab", "LAB-TN-001"))
    for headers in (fpo, lab):
        for action in ("activate", "suspend"):
            assert (
                client.post(
                    f"/api/v1/platform/organizations/{org_key}/{action}",
                    headers=headers,
                ).status_code
                == 403
            )
        assert (
            client.post(
                f"/api/v1/platform/organizations/{org_key}/admins",
                json={"email": "nope@example.com"},
                headers=headers,
            ).status_code
            == 403
        )


def test_admin_is_full_access_platform_operator(client):
    """Admin is the super-admin and must hold every governance route."""
    org_key = _create_fpo(client, _platform_token()).json()["organization_key"]
    admin = auth(make_token("u-admin", "admin"))
    assert client.post(
        f"/api/v1/platform/organizations/{org_key}/activate", headers=admin
    ).status_code == 200
    invite = client.post(
        f"/api/v1/platform/organizations/{org_key}/admins",
        json={"email": "admin-onboarded@example.com"},
        headers=admin,
    )
    assert invite.status_code == 200, invite.text
    assert client.get("/api/v1/platform/organizations", headers=admin).status_code == 200
    assert client.get("/api/v1/platform/beekeepers", headers=admin).status_code == 200
    assert client.get("/api/v1/platform/audit", headers=admin).status_code == 200


def test_activate_and_suspend_lifecycle(client):
    token = _platform_token()
    org_key = _create_fpo(client, token).json()["organization_key"]
    activate = client.post(
        f"/api/v1/platform/organizations/{org_key}/activate", headers=auth(token)
    )
    assert activate.status_code == 200
    assert activate.json()["status"] == "ACTIVE"
    suspend = client.post(
        f"/api/v1/platform/organizations/{org_key}/suspend", headers=auth(token)
    )
    assert suspend.status_code == 200
    assert suspend.json()["status"] == "SUSPENDED"


def test_unknown_organization_actions_404(client):
    token = _platform_token()
    assert (
        client.post(
            "/api/v1/platform/organizations/ORG-999999/activate", headers=auth(token)
        ).status_code
        == 404
    )
    assert (
        client.post(
            "/api/v1/platform/organizations/ORG-999999/admins",
            json={"email": "x@example.com"},
            headers=auth(token),
        ).status_code
        == 404
    )


def test_onboard_initial_admin_then_register_fpo_via_invite(client):
    token = _platform_token()
    org_key = _create_fpo(client, token).json()["organization_key"]
    invite = client.post(
        f"/api/v1/platform/organizations/{org_key}/admins",
        json={"email": "chief@palani.example", "role": "fpo"},
        headers=auth(token),
    )
    assert invite.status_code == 200
    body = invite.json()
    assert body["organization_key"] == org_key
    assert body["role"] == "fpo"
    assert body["token"]

    resp = client.post(
        "/api/v1/auth/register",
        json={
            "email": "chief@palani.example",
            "name": "Chief of Palani FPO",
            "phone": "+919000000042",
            "password": "Str0ngPass!42",
            "role": "fpo",
            "invite_code": body["token"],
        },
    )
    assert resp.status_code == 201
    me = resp.json()
    assert me["role"] == "fpo"
    assert me["org_id"] == org_key
    assert me["org_name"] == "Palani Hills Honey FPO"


def test_fpo_cannot_self_create_with_arbitrary_org_id(client):
    resp = client.post(
        "/api/v1/auth/register",
        json={
            "email": "rogue@palani.example",
            "name": "Rogue",
            "phone": "+919000000043",
            "password": "Str0ngPass!42",
            "role": "fpo",
            "org_id": "ORG-TN-001",
        },
    )
    assert resp.status_code == 409
    assert "invite" in resp.json()["detail"]


def test_invite_is_single_use_and_binds_email_and_org(client):
    token = _platform_token()
    org_key = _create_fpo(client, token).json()["organization_key"]
    invite_token = client.post(
        f"/api/v1/platform/organizations/{org_key}/admins",
        json={"email": "right@palani.example"},
        headers=auth(token),
    ).json()["token"]

    wrong_email = client.post(
        "/api/v1/auth/register",
        json={
            "email": "wrong@palani.example",
            "name": "Wrong",
            "phone": "+919000000044",
            "password": "Str0ngPass!42",
            "role": "fpo",
            "invite_code": invite_token,
        },
    )
    assert wrong_email.status_code == 409

    good = client.post(
        "/api/v1/auth/register",
        json={
            "email": "right@palani.example",
            "name": "Right",
            "phone": "+919000000045",
            "password": "Str0ngPass!42",
            "role": "fpo",
            "invite_code": invite_token,
        },
    )
    assert good.status_code == 201

    replay = client.post(
        "/api/v1/auth/register",
        json={
            "email": "again@palani.example",
            "name": "Again",
            "phone": "+919000000046",
            "password": "Str0ngPass!42",
            "role": "fpo",
            "invite_code": invite_token,
        },
    )
    assert replay.status_code == 409


def test_platform_can_list_organizations_and_others_cannot(client):
    token = _platform_token()
    _create_fpo(client, token)
    resp = client.get("/api/v1/platform/organizations", headers=auth(token))
    assert resp.status_code == 200
    keys = [o["organization_key"] for o in resp.json()]
    assert any(re.fullmatch(r"ORG-\d{6}", k) for k in keys)
    assert (
        client.get(
            "/api/v1/platform/organizations",
            headers=auth(make_token("u-fpo", "fpo", "ORG-TN-001")),
        ).status_code
        == 403
    )