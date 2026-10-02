"""Production persistence must fail closed.

The repository factory used to return an in-memory demo repository whenever
Supabase configuration was missing — including in production. That would let a
public production host serve a synthetic dataset, which is a false claim about
real supply-chain state. These tests pin the corrected behaviour.
"""
from __future__ import annotations

import pytest

from app.db import supabase as db_module


# ---------------------------------------------------------------------------
# Production ledger must fail closed.
#
# The local in-process ledger holds commitments in memory and produces nothing a
# consumer could verify. Letting it serve production would let a public host
# report provenance anchors that exist in no chain while labelling them as if they
# did — the exact failure the honest adapter states exist to prevent. So
# production requires the real Fabric bridge and refuses to start without it.


class _LedgerSettings:
    def __init__(self, *, is_production: bool, **overrides) -> None:
        self.is_production = is_production
        self.blockchain_adapter = "simulated"
        self.fabric_bridge_url = ""
        self.fabric_bridge_token = ""
        self.fabric_channel = ""
        self.fabric_chaincode = ""
        self.fabric_bridge_timeout = 30
        self.blockchain_rpc_url = ""
        self.blockchain_chain_id = ""
        self.blockchain_contract = ""
        self.blockchain_private_key = ""
        self.fabric_gateway_url = ""
        for key, value in overrides.items():
            setattr(self, key, value)


def _gateway_for(**overrides):
    from app.adapters.blockchain.gateway import build_blockchain_gateway

    return build_blockchain_gateway(_LedgerSettings(**overrides))


def test_production_refuses_the_local_ledger():
    with pytest.raises(RuntimeError, match="local in-process ledger"):
        _gateway_for(is_production=True, blockchain_adapter="simulated")


def test_production_refuses_unknown_adapter():
    with pytest.raises(RuntimeError, match="Unknown BLOCKCHAIN_ADAPTER"):
        _gateway_for(is_production=True, blockchain_adapter="banana")


def test_production_remote_fabric_requires_bridge_configuration():
    with pytest.raises(RuntimeError, match="FABRIC_BRIDGE_URL"):
        _gateway_for(is_production=True, blockchain_adapter="remote_fabric")


def test_production_remote_fabric_builds_when_fully_configured():
    """Configured for Fabric, the gateway must report the real adapter."""
    gateway = _gateway_for(
        is_production=True,
        blockchain_adapter="remote_fabric",
        fabric_bridge_url="https://ledger.honeychain.in",
        fabric_bridge_token="not-a-real-token",
        fabric_channel="mychannel",
        fabric_chaincode="honeychain",
    )
    # 'fabric' is the remote bridge. It is not 'local', so production can never
    # silently serve the in-memory ledger.
    assert gateway.ledger_name == "fabric"


def test_development_keeps_the_local_ledger():
    """Development is allowed to use the local ledger — and says so."""
    assert _gateway_for(is_production=False, blockchain_adapter="simulated").ledger_name == (
        "local"
    )


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
