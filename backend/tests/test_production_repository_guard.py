"""Production persistence must fail closed.

The repository factory used to return an in-memory demo repository whenever
Supabase configuration was missing — including in production. That would let a
public production host serve a synthetic dataset, which is a false claim about
real supply-chain state. These tests pin the corrected behaviour.
"""
from __future__ import annotations

import pytest

from app.db import supabase as db_module


class _FakeSettings:
    def __init__(self, *, is_production: bool, url: str = "", key: str = "") -> None:
        self.supabase_url = url
        self.supabase_service_role_key = key
        self.is_production = is_production


def test_production_without_supabase_refuses_startup(monkeypatch):
    monkeypatch.setattr(
        db_module, "get_settings", lambda: _FakeSettings(is_production=True)
    )
    with pytest.raises(RuntimeError, match="refuses to fall back"):
        db_module.build_repository()


def test_production_partial_config_refuses_startup(monkeypatch):
    monkeypatch.setattr(
        db_module,
        "get_settings",
        lambda: _FakeSettings(is_production=True, url="https://x.supabase.co"),
    )
    with pytest.raises(RuntimeError, match="SUPABASE_SERVICE_ROLE_KEY"):
        db_module.build_repository()


def test_production_with_supabase_uses_supabase_repository(monkeypatch):
    monkeypatch.setattr(
        db_module,
        "get_settings",
        lambda: _FakeSettings(
            is_production=True, url="https://x.supabase.co", key="service-role"
        ),
    )
    repo = db_module.build_repository()
    # The Supabase client is created lazily, so constructing the repository must
    # not perform any network call.
    assert isinstance(repo, db_module.SupabaseRepository)


def test_development_without_supabase_uses_in_memory(monkeypatch):
    monkeypatch.setattr(
        db_module, "get_settings", lambda: _FakeSettings(is_production=False)
    )
    repo = db_module.build_repository()
    assert isinstance(repo, db_module.InMemoryRepository)
