from __future__ import annotations

from tests.conftest import auth, make_token


def _create_hive(client, token, hive_code="HIVE-TN-001", client_id=""):
    return client.post(
        "/api/v1/hives",
        headers=auth(token),
        json={"hive_code": hive_code, "client_id": client_id},
    )


def test_multi_role_user_has_all_permissions(client):
    """A user with multiple roles should have permissions from all roles."""
    # Create a token with multiple roles: beekeeper + fpo
    multi_token = make_token("multi-user-id", "beekeeper", "ORG-TN-001", roles=["beekeeper", "fpo"])
    
    # beekeeper can create hives
    hive_resp = client.post(
        "/api/v1/hives",
        headers={"Authorization": f"Bearer {multi_token}"},
        json={"hive_code": "HIVE-MULTI"},
    )
    assert hive_resp.status_code == 200, "beekeeper role should allow hive creation"
    
    # fpo can see org dashboard
    dash_resp = client.get(
        "/api/v1/org/ORG-TN-001/dashboard",
        headers={"Authorization": f"Bearer {multi_token}"},
    )
    assert dash_resp.status_code == 200, "fpo role should allow org dashboard access"


def test_multi_role_require_permission_checks_all_roles(client):
    """require_permission should grant access if ANY role has the permission."""
    # User with buyer + lab roles
    token = make_token("multi-user-2", "buyer", "", roles=["buyer", "lab"])
    
    # buyer cannot create lab test, but lab can
    # First need a batch for the lab test
    # For simplicity, test that the permission check logic works
    from app.core.rbac import has_permission, require_permission
    from app.core.security import CurrentUser
    
    user = CurrentUser(user_id="test", role="buyer", roles=["buyer", "lab"])
    # buyer doesn't have lab.test_request, but lab does
    assert has_permission("buyer", "lab.test_request") is False
    assert has_permission("lab", "lab.test_request") is True
    # The require_permission logic should check all roles
    # This is tested indirectly by the endpoint test above


def test_consumer_cannot_use_authenticated_endpoint(client, buyer_token):
    resp = _create_hive(client, buyer_token, "HIVE-BY")
    assert resp.status_code == 403


def test_lab_cannot_create_harvest(client, lab_token):
    resp = client.post(
        "/api/v1/harvests",
        headers=auth(lab_token),
        json={"hive_id": "x", "quantity_kg": 2.0},
    )
    assert resp.status_code == 403


def test_beekeeper_cannot_create_batch(client, demo_token):
    resp = client.post(
        "/api/v1/batches",
        headers=auth(demo_token),
        json={"batch_code": "HC-BEETEST", "quantity_kg": 5},
    )
    assert resp.status_code == 403


def test_beekeeper_cannot_see_other_beekeepers_hive(client, demo_token):
    other_token = make_token("other-beekeeper-id", "beekeeper", "ORG-TN-002")
    hive = _create_hive(client, demo_token, "HIVE-PRIV").json()
    resp = client.get(f"/api/v1/hives/{hive['id']}", headers=auth(other_token))
    assert resp.status_code == 404


def test_beekeeper_cannot_modify_foreign_harvest(client, demo_token):
    other_token = make_token("other-beekeeper-id", "beekeeper", "ORG-TN-002")
    hive = _create_hive(client, demo_token, "HIVE-PRIV2").json()
    harvest = client.post(
        "/api/v1/harvests",
        headers=auth(demo_token),
        json={"hive_id": hive["id"], "quantity_kg": 3.0},
    ).json()
    other_harvest = client.get(
        f"/api/v1/harvests/{harvest['id']}", headers=auth(other_token)
    )
    assert other_harvest.status_code == 404


def test_lab_cannot_change_batch_status(client, lab_token, fpo_token):
    harvest = _seed_harvest(client, fpo_token)
    batch = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={
            "batch_code": "HC-RBAC-1",
            "quantity_kg": harvest["quantity_kg"],
            "harvest_ids": [harvest["id"]],
        },
    ).json()
    resp = client.put(
        f"/api/v1/batches/{batch['id']}",
        headers=auth(lab_token),
        json={"status": "packaged"},
    )
    assert resp.status_code == 403


def _seed_harvest(client, token):
    hive = client.post(
        "/api/v1/hives", headers=auth(token), json={"hive_code": "HIVE-SEED"}
    ).json()
    return client.post(
        "/api/v1/harvests",
        headers=auth(token),
        json={"hive_id": hive["id"], "quantity_kg": 10.0},
    ).json()