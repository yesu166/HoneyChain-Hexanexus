"""End-to-end coverage for market linkage, QR reuse, and the van.

These tests walk the REAL workflow through the HTTP API — no service is called
directly and no state is faked. Each one asserts that a downstream portal sees
the change, because "the write succeeded" is not the same claim as "the next
actor can see it".
"""
from __future__ import annotations

import pytest

from .conftest import auth, make_token

# Two distinct organizations, so cross-actor routing is genuinely exercised
# rather than accidentally satisfied by a single-org fixture.
SELLER_ORG = "ORG-TEST-SELLER"
BUYER_ORG = "ORG-TEST-BUYER"
LAB_ORG = "ORG-TEST-LAB"


@pytest.fixture()
def seller(client):
    """An FPO that owns the batch it will sell."""
    repo = client.app.state.repository
    repo.ensure_organization(
        {
            "id": SELLER_ORG,
            "name": "Test Hillside FPO",
            "type": "fpo",
            "status": "ACTIVE",
        }
    )
    repo.ensure_organization(
        {
            "id": BUYER_ORG,
            "name": "Test Honey Traders",
            "type": "buyer",
            "status": "ACTIVE",
        }
    )
    repo.ensure_organization(
        {"id": LAB_ORG, "name": "Test Lab", "type": "lab", "status": "ACTIVE"}
    )
    return make_token("seller-user-id", "fpo", SELLER_ORG)


@pytest.fixture()
def buyer(client):
    return make_token("buyer-user-id", "buyer", BUYER_ORG)


@pytest.fixture()
def other_fpo(client):
    client.app.state.repository.ensure_organization(
        {
            "id": "ORG-TEST-OTHER",
            "name": "Other FPO",
            "type": "fpo",
            "status": "ACTIVE",
        }
    )
    return make_token("other-fpo-user-id", "fpo", "ORG-TEST-OTHER")


def _make_verified_batch(client, seller, *, quantity=20.0, code="MK-BATCH-1"):
    """A batch that has genuinely passed the laboratory.

    Built by calling the real lab endpoints rather than by writing a trust_tier
    directly, so the test proves the listing gate sits downstream of a real lab
    PASS instead of being bypassed.
    """
    headers = auth(seller)
    hive = client.post(
        "/api/v1/hives",
        json={"hive_code": "HV-MK-1", "hive_type": "Langstroth", "location": "Nilgiris"},
        headers=headers,
    )
    assert hive.status_code == 201, hive.text
    harvest = client.post(
        "/api/v1/harvests",
        json={"hive_id": hive.json()["id"], "quantity_kg": quantity, "honey_type": "Nilgiri"},
        headers=headers,
    )
    assert harvest.status_code == 201, harvest.text
    batch = client.post(
        "/api/v1/batches",
        json={
            "batch_code": code,
            "honey_type": "Nilgiri",
            "quantity_kg": quantity,
            "harvest_ids": [harvest.json()["id"]],
        },
        headers=headers,
    )
    assert batch.status_code == 201, batch.text
    batch_id = batch.json()["id"]

    test = client.post(
        f"/api/v1/batches/{batch_id}/lab-test",
        json={
            "batch_id": batch_id,
            "lab_id": LAB_ORG,
            "requested_note": "market readiness",
        },
        headers=headers,
    )
    assert test.status_code == 201, test.text
    test_id = test.json()["id"]
    lab_headers = auth(make_token("lab-user-id", "lab", LAB_ORG))
    assert client.post(f"/api/v1/labs/tests/{test_id}/start", headers=lab_headers).status_code == 200
    passed = client.post(
        f"/api/v1/labs/tests/{test_id}/result",
        json={"result": "PASS", "notes": "clear"},
        headers=lab_headers,
    )
    assert passed.status_code == 200, passed.text
    return batch_id


def _verified_listing(client, seller, buyer, *, quantity=10.0, price=450.0, order_qty=None):
    """Verified batch -> open listing -> (optionally) an accepted order."""
    batch_id = _make_verified_batch(client, seller)
    seller_headers, buyer_headers = auth(seller), auth(buyer)
    listing = client.post(
        "/api/v1/market/listings",
        json={"batch_id": batch_id, "quantity_kg": quantity, "price_per_kg": price},
        headers=seller_headers,
    )
    assert listing.status_code == 201, listing.text
    listing_body = listing.json()
    order = None
    if order_qty is not None:
        created = client.post(
            "/api/v1/market/orders",
            json={"listing_id": listing_body["id"], "quantity_kg": order_qty},
            headers=buyer_headers,
        )
        assert created.status_code == 201, created.text
        order = created.json()
    return batch_id, listing_body, order, seller_headers, buyer_headers
    # ------------------------------------------------------------------ market
def test_listing_requires_lab_verification(client, seller):
    """An unverified batch must not be sellable — the gate is real."""
    headers = auth(seller)
    hive = client.post(
        "/api/v1/hives", json={"hive_code": "HV-UNVERIFIED"}, headers=headers
    ).json()
    harvest = client.post(
        "/api/v1/harvests",
        json={"hive_id": hive["id"], "quantity_kg": 5},
        headers=headers,
    ).json()
    batch = client.post(
        "/api/v1/batches",
        json={
            "batch_code": "UNVERIFIED-1",
            "quantity_kg": 5,
            "harvest_ids": [harvest["id"]],
        },
        headers=headers,
    ).json()
    res = client.post(
        "/api/v1/market/listings",
        json={"batch_id": batch["id"], "quantity_kg": 5, "price_per_kg": 400},
        headers=headers,
    )
    assert res.status_code == 400
    assert "laboratory-verified" in res.json()["detail"]


def test_foreign_org_cannot_list_your_batch(client, seller, other_fpo):
    """A batch outside the caller's scope is not even visible to them.

    The route resolves the batch through the caller's own scope first, so an FPO
    asking about another FPO's lot gets 404 — it cannot confirm the lot exists.
    That is deliberate: a 403 would confirm there is something to list.
    """
    batch_id = _make_verified_batch(client, seller)
    res = client.post(
        "/api/v1/market/listings",
        json={"batch_id": batch_id, "quantity_kg": 5, "price_per_kg": 400},
        headers=auth(other_fpo),
    )
    assert res.status_code == 404


def test_full_market_flow_writes_custody_and_notifies(
    client, seller, buyer
):
    """list -> request -> accept -> fulfil, end to end through the API."""
    batch_id, listing_body, order, seller_headers, buyer_headers = _verified_listing(
        client, seller, buyer, quantity=10.0, price=450.0, order_qty=4.0
    )
    assert listing_body["status"] == "OPEN"
    assert listing_body["remaining_kg"] == 10.0
    # The seller org comes from the batch, never from the request body.
    assert listing_body["seller_org_id"] == SELLER_ORG

    # The seller is told their lot is on the market.
    seller_inbox = client.get(
        "/api/v1/notifications", headers=seller_headers
    ).json()
    assert any(n["category"] == "MARKET_LISTED" for n in seller_inbox["items"])

    assert order["status"] == "REQUESTED"
    # The agreed total is persisted, not recomputed later.
    assert order["total_amount"] == 1800.0

    decided = client.post(
        f"/api/v1/market/orders/{order['id']}/decide",
        json={"accept": True, "seller_notes": "confirmed"},
        headers=seller_headers,
    )
    assert decided.status_code == 200, decided.text
    assert decided.json()["status"] == "ACCEPTED"
    # Remaining stock really dropped, so the kilograms are committed.
    refreshed = client.get(
        "/api/v1/market/listings", headers=seller_headers
    ).json()
    assert refreshed[0]["remaining_kg"] == 6.0

    fulfilled = client.post(
        f"/api/v1/market/orders/{order['id']}/fulfil", headers=buyer_headers
    )
    assert fulfilled.status_code == 200, fulfilled.text
    assert fulfilled.json()["status"] == "FULFILLED"

    # The sale is a real custody event on the batch, not just an order status.
    custody = client.get(
        f"/api/v1/batches/{batch_id}/custody-events", headers=seller_headers
    ).json()
    sale = [c for c in custody if c["action"] == "SALE"]
    assert len(sale) == 1, custody
    assert sale[0]["to_org"] == BUYER_ORG
    assert sale[0]["quantity_kg"] == 4.0

    # The buyer was notified from the fulfilment write.
    buyer_inbox = client.get("/api/v1/notifications", headers=buyer_headers).json()
    assert any(
        n["category"] == "BUYER_ACCEPTED" and "Order fulfilled" in n["title"]
        for n in buyer_inbox["items"]
    )


def test_oversell_is_refused(client, seller, buyer):
    """Committed kilograms can never be sold twice.

    `remaining_kg` drops when an order is ACCEPTED, not when it is merely
    requested — several buyers may hold open requests for the same lot. The
    refusal therefore happens at acceptance, which is the moment the kilograms
    would actually be committed.
    """
    _, listing_body, _, seller_headers, buyer_headers = _verified_listing(
        client, seller, buyer, quantity=10.0
    )
    first = client.post(
        "/api/v1/market/orders",
        json={"listing_id": listing_body["id"], "quantity_kg": 7.0},
        headers=buyer_headers,
    ).json()
    # A request larger than the whole remaining lot is refused: a conflict with
    # the listing's current state, not malformed input.
    too_big = client.post(
        "/api/v1/market/orders",
        json={"listing_id": listing_body["id"], "quantity_kg": 11.0},
        headers=buyer_headers,
    )
    assert too_big.status_code == 409
    assert "remain" in too_big.json()["detail"]

    # A second buyer may also request, but only 3 kg are left after the first
    # acceptance, so accepting their 5 kg would oversell and must be refused.
    second = client.post(
        "/api/v1/market/orders",
        json={"listing_id": listing_body["id"], "quantity_kg": 5.0},
        headers=buyer_headers,
    )
    assert second.status_code == 201, second.text

    accepted = client.post(
        f"/api/v1/market/orders/{first['id']}/decide",
        json={"accept": True},
        headers=seller_headers,
    )
    assert accepted.status_code == 200, accepted.text
    now = client.get("/api/v1/market/listings", headers=seller_headers).json()
    assert now[0]["remaining_kg"] == 3.0

    oversell = client.post(
        f"/api/v1/market/orders/{second.json()['id']}/decide",
        json={"accept": True},
        headers=seller_headers,
    )
    assert oversell.status_code == 409
    assert "remain" in oversell.json()["detail"]
    # The rejected acceptance left the stock untouched.
    after = client.get("/api/v1/market/listings", headers=seller_headers).json()
    assert after[0]["remaining_kg"] == 3.0
    assert after[0]["status"] == "OPEN"


def test_seller_cannot_buy_own_listing(client, seller):
    _, listing_body, _, seller_headers, _ = _verified_listing(
        client, seller, make_token("buyer-user-id", "buyer", BUYER_ORG), quantity=5.0
    )
    own = client.post(
        "/api/v1/market/orders",
        json={"listing_id": listing_body["id"], "quantity_kg": 1.0},
        headers=seller_headers,
    )
    assert own.status_code == 403


def test_accepted_order_cannot_be_cancelled(client, seller, buyer):
    _, listing_body, order, seller_headers, buyer_headers = _verified_listing(
        client, seller, buyer, quantity=5.0, order_qty=2.0
    )
    client.post(
        f"/api/v1/market/orders/{order['id']}/decide",
        json={"accept": True},
        headers=seller_headers,
    )
    cancel = client.post(
        f"/api/v1/market/orders/{order['id']}/cancel", headers=buyer_headers
    )
    assert cancel.status_code == 409
    # ---------------------------------------------------------------------- QR
@pytest.fixture()
def packaged_batch(client, seller):
    """A verified batch with one issued package label."""
    batch_id = _make_verified_batch(client, seller, code="QR-BATCH-1")
    headers = auth(seller)
    issued = client.post(
        "/api/v1/qr/packages",
        json={"batch_id": batch_id, "quantity_kg": 2.0, "package_code": "HC-TEST-0001"},
        headers=headers,
    )
    assert issued.status_code == 201, issued.text
    return batch_id, issued.json(), headers


def test_first_scan_is_clean(client, packaged_batch, buyer):
    _, package, _ = packaged_batch
    res = client.post(
        "/api/v1/qr/scan",
        json={"package_code": "HC-TEST-0001"},
        headers=auth(buyer),
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["result"] == "CLEAR"
    # A clean scan carries no signals at all — the detector invents nothing.
    assert body["signals"] == []
    assert body["package"]["status"] == "SCANNED"
    assert body["package"]["scan_count"] == 1


def test_second_scan_by_other_org_is_flagged_as_reuse(
    client, packaged_batch, buyer, other_fpo
):
    """The classic cloned-label case: a different org presents the same code."""
    _, package, seller_headers = packaged_batch
    first = client.post(
        "/api/v1/qr/scan",
        json={"package_code": "HC-TEST-0001"},
        headers=auth(make_token("retailer-user-id", "processor", "ORG-TEST-RETAIL")),
    )
    assert first.json()["result"] == "CLEAR"

    second = client.post(
        "/api/v1/qr/scan",
        json={"package_code": "HC-TEST-0001"},
        headers=auth(other_fpo),
    )
    assert second.status_code == 200, second.text
    body = second.json()
    assert body["result"] == "SUSPICIOUS"
    codes = [s["code"] for s in body["signals"]]
    assert "REUSE_BY_OTHER_ORG" in codes, body
    # The signal is persisted, so an auditor can see why it was flagged.
    assert body["scan"]["signals"]

    # The issuer is alerted from the same write that recorded the scan.
    inbox = client.get("/api/v1/notifications", headers=seller_headers).json()
    assert any(
        n["category"] == "QR_SUSPICIOUS" and n["severity"] == "critical"
        for n in inbox["items"]
    ), inbox
    flagged = client.get("/api/v1/qr/scans", headers=seller_headers).json()
    assert any(s["result"] == "SUSPICIOUS" for s in flagged)


def test_duplicate_print_is_detected(client, packaged_batch, buyer):
    """Re-printing the same code does not mint a second package."""
    _, package, seller_headers = packaged_batch
    client.post(
        "/api/v1/qr/scan",
        json={"package_code": "HC-TEST-0001"},
        headers=auth(buyer),
    )
    reprint = client.post(
        "/api/v1/qr/packages",
        json={
            "batch_id": package["batch_id"],
            "quantity_kg": 2.0,
            "package_code": "HC-TEST-0001",
        },
        headers=seller_headers,
    )
    # The second label resolves to the package that already owns the identity.
    assert reprint.json()["id"] == package["id"]
    packages = client.get("/api/v1/qr/packages", headers=seller_headers).json()
    assert len(packages) == 1

    again = client.post(
        "/api/v1/qr/scan",
        json={"package_code": "HC-TEST-0001"},
        headers=auth(buyer),
    )
    assert again.json()["result"] == "SUSPICIOUS"
    assert "DUPLICATE_PRINT" in [s["code"] for s in again.json()["signals"]]


def test_unissued_code_is_recorded_and_flagged(client, seller):
    """An unknown label is itself evidence, so the scan is still persisted."""
    res = client.post(
        "/api/v1/qr/scan",
        json={"package_code": "HC-NEVER-ISSUED"},
        headers=auth(seller),
    )
    assert res.status_code == 200
    body = res.json()
    assert body["result"] == "SUSPICIOUS"
    assert body["package"] is None
    assert body["signals"][0]["code"] == "UNKNOWN_CODE"
    assert body["scan"]["id"]


def test_recalled_package_is_flagged(client, packaged_batch, buyer):
    _, package, seller_headers = packaged_batch
    recalled = client.post(
        "/api/v1/qr/packages/HC-TEST-0001/recall", headers=seller_headers
    )
    assert recalled.status_code == 200, recalled.text
    assert recalled.json()["status"] == "RECALLED"
    res = client.post(
        "/api/v1/qr/scan",
        json={"package_code": "HC-TEST-0001"},
        headers=auth(buyer),
    )
    assert "RECALLED" in [s["code"] for s in res.json()["signals"]]
    # --------------------------------------------------------------------- van
def test_van_visit_requires_arrival_before_sampling(client, seller):
    headers = auth(seller)
    kvic = auth(make_token("officer-user-id", "institution", "ORG-TEST-KVIC"))
    visit = client.post(
        "/api/v1/van/visits",
        json={"van_code": "VAN-1", "target_name": "Hillside apiary"},
        headers=kvic,
    )
    assert visit.status_code == 201, visit.text
    visit_id = visit.json()["id"]

    batch_id = _make_verified_batch(client, seller)
    early = client.post(
        f"/api/v1/van/visits/{visit_id}/samples",
        json={"batch_id": batch_id, "sample_code": "SMP-1"},
        headers=kvic,
    )
    assert early.status_code == 409
    assert "on site" in early.json()["detail"]

    arrived = client.post(f"/api/v1/van/visits/{visit_id}/advance", headers=kvic)
    assert arrived.json()["status"] == "ARRIVED"
    sample = client.post(
        f"/api/v1/van/visits/{visit_id}/samples",
        json={"batch_id": batch_id, "sample_code": "SMP-1", "quantity_kg": 0.5},
        headers=kvic,
    )
    assert sample.status_code == 201, sample.text
    # The visit advanced because a sample genuinely exists.
    assert sample.json()["result"] == "PENDING"

    done = client.post(f"/api/v1/van/visits/{visit_id}/advance", headers=kvic)
    assert done.status_code == 200, done.text
    assert done.json()["status"] == "COMPLETED"

    # The owning FPO learns a sample was taken from its batch.
    inbox = client.get("/api/v1/notifications", headers=headers).json()
    assert any(n["category"] == "VAN_SAMPLE_RECEIVED" for n in inbox["items"])


def test_van_sample_against_unknown_batch_is_refused(client):
    kvic = auth(make_token("officer-user-id", "institution", "ORG-TEST-KVIC"))
    visit = client.post(
        "/api/v1/van/visits", json={"van_code": "VAN-2"}, headers=kvic
    ).json()
    client.post(f"/api/v1/van/visits/{visit['id']}/advance", headers=kvic)
    res = client.post(
        f"/api/v1/van/visits/{visit['id']}/samples",
        json={"batch_id": "batch-that-does-not-exist", "sample_code": "SMP-X"},
        headers=kvic,
    )
    assert res.status_code == 400
    assert "batch not found" in res.json()["detail"].lower()


def test_van_result_never_certifies_the_batch(client, seller):
    """A van observation must not be presentable as a lab certificate."""
    headers = auth(seller)
    kvic = auth(make_token("officer-user-id", "institution", "ORG-TEST-KVIC"))
    batch_id = _make_verified_batch(client, seller, code="VAN-BATCH-1")
    before = client.get(f"/api/v1/batches/{batch_id}", headers=headers).json()

    visit = client.post(
        "/api/v1/van/visits", json={"van_code": "VAN-3"}, headers=kvic
    ).json()
    client.post(f"/api/v1/van/visits/{visit['id']}/advance", headers=kvic)
    sample = client.post(
        f"/api/v1/van/visits/{visit['id']}/samples",
        json={"batch_id": batch_id, "sample_code": "SMP-V1"},
        headers=kvic,
    ).json()

    result = client.post(
        f"/api/v1/van/samples/{sample['id']}/result",
        json={"result": "PASS", "notes": "field moisture ok"},
        headers=kvic,
    )
    assert result.status_code == 200, result.text
    # Explicitly flagged, and the trust tier is echoed unchanged.
    assert result.json()["is_laboratory_certificate"] is False
    after = client.get(f"/api/v1/batches/{batch_id}", headers=headers).json()
    assert after["trust_tier"] == before["trust_tier"]


def test_package_passport_is_public_and_live(client, seller, buyer):
    """A printed label's code resolves to a real public passport.

    This is the live-QR contract: the label carries an identity, a phone camera
    opens the public route, and the backend answers with the batch's CURRENT
    provenance. Nothing is baked into the QR.
    """
    batch_id = _make_verified_batch(client, seller, code="QR-PASS-1")
    issued = client.post(
        "/api/v1/qr/packages",
        json={"batch_id": batch_id, "quantity_kg": 5},
        headers=auth(seller),
    )
    assert issued.status_code == 201, issued.text
    code = issued.json()["package_code"]
    # The issuer is handed the live public route, not passport data.
    assert issued.json()["passport_path"] == f"/api/v1/passport/package/{code}"

    # No auth header at all: this is the consumer path.
    public = client.get(f"/api/v1/passport/package/{code}")
    assert public.status_code == 200, public.text
    body = public.json()
    assert body["subject_code"] == "QR-PASS-1"
    assert body["trust_tier"] == "lab_verified"
    assert body["raw"]["package_code"] == code
    # PII-free: no person, phone or email anywhere in the public payload.
    blob = str(body).lower()
    for leak in ("@", "phone", "email", "password"):
        assert leak not in blob, f"public passport leaked {leak}"

    # An unknown label is a 404 — never an invented product.
    missing = client.get("/api/v1/passport/package/HC-NEVER-ISSUED-XYZ")
    assert missing.status_code == 404


def test_package_passport_reflects_later_changes(client, seller, buyer):
    """The package passport is rebuilt from live records, not frozen."""
    batch_id = _make_verified_batch(client, seller, code="QR-PASS-2")
    code = client.post(
        "/api/v1/qr/packages",
        json={"batch_id": batch_id, "quantity_kg": 5},
        headers=auth(seller),
    ).json()["package_code"]

    before = client.get(f"/api/v1/passport/package/{code}").json()
    stages_before = {e["type"] for e in before["events"]}

    # A real custody write after the label was issued.
    client.post(
        f"/api/v1/batches/{batch_id}/custody-events",
        headers=auth(seller),
        json={"batch_id": batch_id, "action": "SALE", "actor": "fpo"},
    )

    after = client.get(f"/api/v1/passport/package/{code}").json()
    stages_after = {e["type"] for e in after["events"]}
    assert "SALE" in stages_after
    assert stages_after != stages_before


def test_ledger_never_claims_fabric_in_development(client):
    """Development keeps the local ledger, and says so honestly."""
    from app.adapters.blockchain.gateway import build_blockchain_gateway

    gateway = build_blockchain_gateway(client.app.state.settings)
    # The test session is explicitly the simulated/local adapter.
    assert gateway.ledger_name == "local", (
        "a development session must not report a real chain it did not use"
    )


def test_van_is_closed_to_non_officer_roles(client):
    """A buyer may not open the field-officer submodule."""
    res = client.get(
        "/api/v1/van/dashboard",
        headers=auth(make_token("buyer-user-id", "buyer", "ORG-TEST-BUYER")),
    )
    assert res.status_code == 403
    """A buyer may not open the field-officer submodule."""
    res = client.get(
        "/api/v1/van/dashboard",
        headers=auth(make_token("buyer-user-id", "buyer", "ORG-TEST-BUYER")),
    )
    assert res.status_code == 403