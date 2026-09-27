"""Regression: an omitted `client_id` must never surface as `None`.

`client_id` is nullable in PostgreSQL by design — the idempotent-sync indexes
are declared `where client_id is not null` (see
`supabase/migrations/005_idempotent_sync_support.sql`), so NULL is the canonical
"no client-supplied id" value and many rows may legitimately share it. Writing
'' instead would collide on those unique indexes.

The API schemas (`HiveRead`, `HarvestRead`) type `client_id` as `str`, and
`InMemoryRepository` always stores a string, so `SupabaseRepository` must
translate NULL back to "" on the read path.

Without that translation `POST /api/v1/hives` without a `client_id` returned
HTTP 500 (ResponseValidationError: response.client_id, input: None) against live
Supabase, while every in-memory test stayed green — because
`InMemoryRepository.create_hive` unconditionally writes `"client_id": client_id`.
These tests pin the contract so that divergence cannot return.
"""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.db.supabase import InMemoryRepository, SupabaseRepository
from app.schemas.harvest import HarvestRead
from app.schemas.hive import HiveRead
from tests.conftest import auth

NULL_HIVE_ROW = {
    "id": "11111111-1111-1111-1111-111111111111",
    "beekeeper_id": "beekeeper-1",
    "hive_code": "HIVE-NULL-1",
    "status": "active",
    "location": "Kotagiri",
    "client_id": None,
}

NULL_HARVEST_ROW = {
    "id": "22222222-2222-2222-2222-222222222222",
    "hive_id": NULL_HIVE_ROW["id"],
    "beekeeper_id": "beekeeper-1",
    "harvested_at": "2026-01-01T00:00:00+00:00",
    "quantity_kg": 4.5,
    "honey_type": "Not specified",
    "collected": False,
    "client_id": None,
}


# --- the failure mode this fix removes -------------------------------------


def test_untranslated_null_client_id_is_rejected_by_the_response_schema():
    """The raw PostgreSQL row is exactly what used to produce HTTP 500."""
    assert NULL_HIVE_ROW["client_id"] is None
    with pytest.raises(ValidationError):
        HiveRead.model_validate(NULL_HIVE_ROW)
    with pytest.raises(ValidationError):
        HarvestRead.model_validate(NULL_HARVEST_ROW)


# --- the production normalization on the read path -------------------------


def test_supabase_hive_row_normalizes_null_client_id_to_empty_string():
    normalized = SupabaseRepository._with_client_id(NULL_HIVE_ROW)
    assert normalized["client_id"] == ""
    assert isinstance(normalized["client_id"], str)
    HiveRead.model_validate(normalized)


def test_supabase_harvest_row_normalizes_null_client_id_to_empty_string():
    normalized = SupabaseRepository._with_client_id(NULL_HARVEST_ROW)
    assert normalized["client_id"] == ""
    assert isinstance(normalized["client_id"], str)
    HarvestRead.model_validate(normalized)


def test_normalization_preserves_a_real_client_id():
    row = {**NULL_HIVE_ROW, "client_id": "client-hive-1"}
    assert SupabaseRepository._with_client_id(row)["client_id"] == "client-hive-1"


def test_normalization_leaves_none_rows_alone():
    assert SupabaseRepository._with_client_id(None) is None


def test_list_normalization_covers_every_row():
    rows = [
        NULL_HIVE_ROW,
        {**NULL_HIVE_ROW, "id": "33333333-3333-3333-3333-333333333333"},
        {**NULL_HIVE_ROW, "id": "44444444-4444-4444-4444-444444444444", "client_id": "c"},
    ]
    out = SupabaseRepository._with_client_id_list(rows)
    assert [r["client_id"] for r in out] == ["", "", "c"]
    for row in out:
        HiveRead.model_validate(row)


# --- the application contract, end to end through the API ------------------


def test_create_hive_without_client_id_returns_empty_string(client, demo_token):
    resp = client.post(
        "/api/v1/hives",
        headers=auth(demo_token),
        json={"hive_code": "HIVE-NO-CLIENT-ID"},
    )
    assert resp.status_code == 201
    hive = resp.json()
    assert isinstance(hive["client_id"], str)
    assert hive["client_id"] == ""

    fetched = client.get(f"/api/v1/hives/{hive['id']}", headers=auth(demo_token))
    assert fetched.status_code == 200
    assert fetched.json()["client_id"] == ""

    listed = client.get("/api/v1/hives", headers=auth(demo_token))
    assert listed.status_code == 200
    assert all(isinstance(h["client_id"], str) for h in listed.json())


def test_create_harvest_without_client_id_returns_empty_string(client, demo_token):
    hive = client.post(
        "/api/v1/hives",
        headers=auth(demo_token),
        json={"hive_code": "HIVE-NO-CLIENT-ID-H"},
    ).json()
    resp = client.post(
        "/api/v1/harvests",
        headers=auth(demo_token),
        json={"hive_id": hive["id"], "quantity_kg": 5.0},
    )
    assert resp.status_code == 201
    harvest = resp.json()
    assert isinstance(harvest["client_id"], str)
    assert harvest["client_id"] == ""

    fetched = client.get(f"/api/v1/harvests/{harvest['id']}", headers=auth(demo_token))
    assert fetched.status_code == 200
    assert fetched.json()["client_id"] == ""


# --- repository parity ------------------------------------------------------


def test_inmemory_and_supabase_agree_when_client_id_is_omitted():
    """The two repositories must present the same shape for the omitted case."""
    stored = InMemoryRepository().create_hive(
        {"beekeeper_id": "beekeeper-1", "hive_code": "HIVE-PARITY"}
    )
    assert stored["client_id"] == ""
    assert (
        SupabaseRepository._with_client_id(NULL_HIVE_ROW)["client_id"]
        == stored["client_id"]
    )


def test_batch_contract_normalizes_nullable_string_fields():
    rows = [
        {"id": "b1", "organization_id": None, "client_id": None},
        {"id": "b2", "organization_id": "org-1", "client_id": None},
    ]
    out = SupabaseRepository._with_batch_contract_list(rows)

    assert out[0]["organization_id"] == ""
    assert out[0]["client_id"] == ""
    assert out[1]["organization_id"] == "org-1"
    assert out[1]["client_id"] == ""


def test_batch_contract_leaves_none_row_alone():
    assert SupabaseRepository._with_batch_contract(None) is None
