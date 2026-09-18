from __future__ import annotations

import uuid

from tests.conftest import auth


def _seed_batch(client, token, code, qty):
    """Hive -> harvest -> batch through the public API (real data flow)."""
    hive = client.post(
        "/api/v1/hives", headers=auth(token), json={"hive_code": "HIVE-TA"}
    ).json()
    harvest = client.post(
        "/api/v1/harvests",
        headers=auth(token),
        json={"hive_id": hive["id"], "quantity_kg": qty},
    ).json()
    resp = client.post(
        "/api/v1/batches",
        headers=auth(token),
        json={
            "batch_code": code,
            "quantity_kg": qty,
            "harvest_ids": [harvest["id"]],
            "organization_id": "ORG-TN-001",
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def _handover_to_processor(client, fpo_token, batch_id):
    """Record the real physical handover: the FPO TRANSFERs custody of the
    batch to the processor actor. The receiving actor is then legitimately in
    scope to assert facts (receipt quantities) about the material."""
    resp = client.post(
        f"/api/v1/batches/{batch_id}/custody-events",
        headers=auth(fpo_token),
        json={
            "batch_id": batch_id,
            "action": "TRANSFER",
            "actor": "fpo-user-id",
            "notes": "dispatch to processor",
            "to_actor": "processor-user-id",
        },
    )
    assert resp.status_code == 201, resp.text


def _assert(client, token, batch_id, *, action, subject, qty=None, org="ORG-TN-001", **extra):
    body = {
        "entity_type": "batch",
        "entity_ref": batch_id,
        "action": action,
        "subject": subject,
        "organization_ref": org,
        "client_id": uuid.uuid4().hex,
    }
    if qty is not None:
        body["asserted_quantity_kg"] = qty
    body.update(extra)
    return client.post("/api/v1/assertions", headers=auth(token), json=body)


# ---------------------------------------------------------------------------
# Capability A/C — assertions preserve WHO asserted WHAT, both sides kept
# ---------------------------------------------------------------------------
def test_two_org_quantity_conflict_is_preserved_not_overwritten(client, fpo_token, processor_token):
    """TEST 2: collector asserts 100 kg, processor asserts 98.6 kg -> a
    discrepancy is opened with BOTH assertions retained; neither is erased."""
    batch = _seed_batch(client, fpo_token, f"TA-C-{uuid.uuid4().hex[:8]}", 100.0)
    first = _assert(
        client, fpo_token, batch["id"], action="COLLECTION", subject="received_quantity",
        qty=100.0, org="ORG-TN-001",
    )
    assert first.status_code == 201, first.text
    # The processor asserts through its own authenticated token with no
    # organization_ref override — the server derives the caller's org, which is
    # the honest path (an actor can never assert AS another org). Scope comes from
    # the recorded physical handover, not from a role override.
    _handover_to_processor(client, fpo_token, batch["id"])
    second = _assert(
        client, processor_token, batch["id"], action="COLLECTION", subject="received_quantity",
        qty=98.6, org="",
    )
    assert second.status_code == 201, second.text
    processor_org = second.json()["organization_ref"]

    report = client.post(
        f"/api/v1/assertions/{batch['id']}/reconcile",
        headers=auth(fpo_token),
        json={"subject": "received_quantity"},
    )
    assert report.status_code == 200, report.text
    body = report.json()
    assert body["open_count"] >= 1
    disc = body["open_discrepancies"][0]
    assert disc["reference"]["organization_ref"] == "ORG-TN-001"
    assert disc["claimant"]["organization_ref"] == processor_org
    assert abs(disc["delta_kg"] - 1.4) < 1e-6

    # Both original assertions still readable — nothing was overwritten.
    rows = client.get(
        f"/api/v1/assertions/{batch['id']}", headers=auth(fpo_token)
    ).json()
    values = sorted(r["asserted_quantity_kg"] for r in rows if r["subject"] == "received_quantity")
    assert values == [98.6, 100.0]


def test_within_tolerance_does_not_raise_discrepancy(client, fpo_token, processor_token):
    """Rounding noise inside the documented band must not create a conflict."""
    batch = _seed_batch(client, fpo_token, f"TA-T-{uuid.uuid4().hex[:8]}", 10.0)
    _assert(client, fpo_token, batch["id"], action="COLLECTION", subject="received_quantity",
            qty=10.0, org="ORG-TN-001")
    # 10.02 vs 10 kg = 0.02 kg; band = max(0.01, 0.5% * 10 = 0.05) -> within.
    _handover_to_processor(client, fpo_token, batch["id"])
    second = _assert(client, processor_token, batch["id"], action="COLLECTION", subject="received_quantity",
            qty=10.02, org="")
    assert second.status_code == 201, second.text
    report = client.post(
        f"/api/v1/assertions/{batch['id']}/reconcile", headers=auth(fpo_token), json={}
    ).json()
    assert report["open_count"] == 0


def test_discrepancy_resolution_is_append_only(client, fpo_token, processor_token):
    """Resolve -> UNDER_REVIEW then RESOLVED; the original record is untouched."""
    batch = _seed_batch(client, fpo_token, f"TA-R-{uuid.uuid4().hex[:8]}", 8.0)
    _assert(client, fpo_token, batch["id"], action="COLLECTION", subject="received_quantity",
            qty=8.0, org="ORG-TN-001")
    _handover_to_processor(client, fpo_token, batch["id"])
    second = _assert(client, processor_token, batch["id"], action="COLLECTION", subject="received_quantity",
            qty=7.0, org="")
    assert second.status_code == 201, second.text
    disc = client.post(
        f"/api/v1/assertions/{batch['id']}/reconcile", headers=auth(fpo_token), json={}
    ).json()["open_discrepancies"][0]

    mid = client.post(
        f"/api/v1/assertions/{batch['id']}/discrepancies/{disc['discrepancy_id']}/resolve",
        headers=auth(fpo_token), json={"state": "UNDER_REVIEW", "note": "investigating"},
    )
    assert mid.status_code == 200, mid.text
    fin = client.post(
        f"/api/v1/assertions/{batch['id']}/discrepancies/{disc['discrepancy_id']}/resolve",
        headers=auth(fpo_token), json={"state": "RESOLVED", "note": "re-weigh confirmed 8.0"},
    )
    assert fin.status_code == 200, fin.text
    assert fin.json()["discrepancy"]["status"] == "RESOLVED"

    rows = client.get(
        f"/api/v1/assertions/{batch['id']}/discrepancies", headers=auth(fpo_token)
    ).json()
    assert rows["open_count"] == 0
    assert len(rows["discrepancies"]) >= 1


def test_declared_authority_is_clamped_down(client, fpo_token):
    """A caller may never grant itself LAB_VERIFIED / AUTHORITY_VERIFIED."""
    batch = _seed_batch(client, fpo_token, f"TA-A-{uuid.uuid4().hex[:8]}", 5.0)
    resp = _assert(
        client, fpo_token, batch["id"], action="COLLECTION", subject="received_quantity",
        qty=5.0, declared_authority="LAB_VERIFIED",
    )
    assert resp.status_code == 201, resp.text
    row = resp.json()
    assert row["authority"] != "LAB_VERIFIED"
    assert row["authority_clamped"] is True


def test_missing_quantity_is_rejected_not_zero(client, fpo_token):
    batch = _seed_batch(client, fpo_token, f"TA-Z-{uuid.uuid4().hex[:8]}", 5.0)
    resp = _assert(client, fpo_token, batch["id"], action="COLLECTION",
                   subject="received_quantity", qty=None)
    assert resp.status_code == 409, resp.text
    assert "never recorded as zero" in resp.json()["detail"]


def test_lab_pass_elevates_and_adverse_assertion_flags_review(client, fpo_token, lab_token):
    """TEST 4 (state part): lab PASS -> LAB_VERIFIED; later adverse evidence ->
    UNDER_REVIEW while the historical PASS stays in history."""
    batch = _seed_batch(client, fpo_token, f"TA-L-{uuid.uuid4().hex[:8]}", 8.0)
    test = client.post(
        f"/api/v1/batches/{batch['id']}/lab-test",
        headers=auth(fpo_token), json={"batch_id": batch["id"]},
    ).json()
    passed = client.post(
        f"/api/v1/labs/tests/{test['id']}/result",
        headers=auth(lab_token), json={"result": "PASS"},
    )
    assert passed.status_code == 200, passed.text

    state = client.get(
        f"/api/v1/assertions/{batch['id']}/verification", headers=auth(fpo_token)
    ).json()
    assert state["current_verification_level"] == "LAB_VERIFIED"
    assert state["review_state"] == "CLEAR"

    adverse = _assert(client, fpo_token, batch["id"], action="COLLECTION",
                      subject="received_quantity", qty=8.0, nature="adverse",
                      note="post-test container leak suspected")
    assert adverse.status_code == 201, adverse.text
    state2 = client.get(
        f"/api/v1/assertions/{batch['id']}/verification", headers=auth(fpo_token)
    ).json()
    assert state2["review_state"] == "UNDER_REVIEW"
    hist = [h for h in state2["historical"] if h["type"] == "LAB_TEST"]
    assert any(h["status"] == "passed" for h in hist)


# ---------------------------------------------------------------------------
# Capability D — downstream impact traversal over existing genealogy
# ---------------------------------------------------------------------------
def test_upstream_issue_identifies_affected_descendants(client, fpo_token):
    """TEST 5: batches A and B merged into M -> impact on A must reach M; the
    marker is an append-only REVIEW_REQUIRED task, not a verdict."""
    a = _seed_batch(client, fpo_token, f"TA-I-A-{uuid.uuid4().hex[:6]}", 5.0)
    b = _seed_batch(client, fpo_token, f"TA-I-B-{uuid.uuid4().hex[:6]}", 5.0)
    merged = client.post(
        "/api/v1/batches/merge",
        headers=auth(fpo_token),
        json={"batch_ids": [a["id"], b["id"]],
              "new_batch_code": f"TA-I-M-{uuid.uuid4().hex[:6]}"},
    )
    assert merged.status_code == 200, merged.text
    merged_id = merged.json()["merged"]["id"]

    impact = client.post(
        f"/api/v1/assertions/{a['id']}/impact",
        headers=auth(fpo_token),
        json={"reason": "upstream hive contamination confirmed", "status": "REVIEW_REQUIRED"},
    )
    assert impact.status_code == 200, impact.text
    body = impact.json()
    assert body["affected_count"] >= 1
    assert any(r["batch_id"] == merged_id for r in body["affected"])
    assert body["recorded"] is True
    assert body["ledger_hashes"], "impact markers must be ledger-anchored"

    rows = client.get(
        f"/api/v1/assertions/{merged_id}/impacts", headers=auth(fpo_token)
    ).json()
    assert rows["count"] >= 1


def test_offline_assertion_sync_is_idempotent(client, fpo_token):
    """TEST 8: the same client_id pushed twice yields ONE ledger assertion."""
    batch = _seed_batch(client, fpo_token, f"TA-O-{uuid.uuid4().hex[:8]}", 3.0)
    item = {
        "entity_type": "batch",
        "entity_ref": batch["id"],
        "action": "COLLECTION",
        "subject": "received_quantity",
        "asserted_quantity_kg": 3.0,
        "organization_ref": "ORG-TN-001",
        "captured_at": "2026-09-18T06:00:00+00:00",
        "device_id": "flutter-test-device",
        "client_id": f"offline-{uuid.uuid4().hex[:10]}",
    }
    first = client.post(
        "/api/v1/sync/push", headers=auth(fpo_token),
        json={"items": [{"entity": "quantity_assertion", "client_id": item["client_id"],
                         "data": item}]},
    )
    assert first.status_code == 200, first.text
    body = first.json()
    assert body["accepted"] and body["accepted"][0]["accepted"] is True, body

    replay = client.post(
        "/api/v1/sync/push", headers=auth(fpo_token),
        json={"items": [{"entity": "quantity_assertion", "client_id": item["client_id"],
                         "data": item}]},
    ).json()
    assert replay["accepted"], replay
    assert replay["accepted"][0].get("deduplicated") is True, replay

    rows = client.get(
        f"/api/v1/assertions/{batch['id']}", headers=auth(fpo_token)
    ).json()
    assert sum(1 for r in rows if r.get("client_id") == item["client_id"]) == 1


def test_assertion_records_server_side_actor_and_role(client, fpo_token, processor_token):
    """TEST 9 (assertion layer): actor_ref/actor_role come from the JWT; the
    server derives organization_ref when the caller omits it."""
    batch = _seed_batch(client, fpo_token, f"TA-X-{uuid.uuid4().hex[:8]}", 4.0)
    _handover_to_processor(client, fpo_token, batch["id"])
    resp = _assert(client, processor_token, batch["id"], action="COLLECTION",
                   subject="received_quantity", qty=4.0, org="")
    assert resp.status_code == 201, resp.text
    row = resp.json()
    assert row["actor_role"] == "processor"
    assert row["actor_ref"] == "processor-user-id"
