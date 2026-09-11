from __future__ import annotations

import pytest

from app.adapters.blockchain.gateway import (
    BlockchainGateway,
    EVMBlockchainAdapter,
    FabricBlockchainAdapter,
    LedgerNotConfigured,
    LedgerUnavailable,
    LocalLedgerAdapter,
    build_blockchain_gateway,
)
from app.adapters.blockchain.state import TxState


def test_local_ledger_anchor_confirms():
    gw = build_blockchain_gateway()
    tx = gw.submit_anchor(batch_id="B-BLOCK-1", evidence_root="0" * 64)
    assert tx["state"] == TxState.CONFIRMED
    assert tx["tx_hash"].startswith("LOCAL-")


def test_local_verify_honest():
    gw = build_blockchain_gateway()
    tx = gw.submit_anchor(batch_id="B-BLOCK-2", evidence_root="1" * 64)
    assert gw.verify_anchor(tx["tx_hash"]) is True
    assert gw.verify_anchor("nope") is False


def test_evm_adapter_reports_not_configured():
    adapter = EVMBlockchainAdapter()
    gw = BlockchainGateway(adapter)
    assert adapter.configured is False
    tx = gw.submit_anchor(batch_id="X", evidence_root="2" * 64)
    assert "NOT_CONFIGURED" in tx["error"]
    assert tx["state"] in (TxState.FAILED, TxState.UNKNOWN)
    assert gw.verify_anchor("anything") is False


def test_fabric_adapter_reports_fabric_not_configured():
    adapter = FabricBlockchainAdapter()
    gw = BlockchainGateway(adapter)
    with pytest.raises(LedgerNotConfigured):
        adapter.submit_anchor({}, "tx-ref")
    tx = gw.submit_event(event={"type": "batch_state_transition", "batch_id": "B-FAB"})
    assert "FABRIC_NOT_CONFIGURED" in tx["error"]


def test_gateway_defaults_to_local():
    gw = build_blockchain_gateway()
    assert gw.ledger_name == "local"


def test_fabric_with_channel_still_unavailable_not_faked():
    with pytest.raises((LedgerNotConfigured, LedgerUnavailable)):
        FabricBlockchainAdapter(channel="honeychain", chaincode="tracer").submit_anchor({}, "t")


def test_evm_with_config_is_boundary_not_simulated():
    adapter = EVMBlockchainAdapter(
        rpc_url="http://x", chain_id="1", contract_address="0x0", private_key_hex="00"
    )
    assert adapter.configured is True
    with pytest.raises(LedgerUnavailable):
        adapter.submit_anchor({"x": 1}, "t")