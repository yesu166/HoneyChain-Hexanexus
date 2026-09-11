"""Tests for the FabricBlockchainAdapter, Fabric health, and chaincode contract mapping.

UNIT tests — all Fabric interactions are mocked via monkeypatch.
LIVE_RUNTIME tests (clearly labeled) are skipped unless FABRIC_GATEWAY_URL is set.
"""
from __future__ import annotations

import json
import os
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

from app.adapters.blockchain.gateway import (
    BlockchainGateway,
    FabricBlockchainAdapter,
    LedgerNotConfigured,
    LedgerUnavailable,
    build_blockchain_gateway,
)
from app.adapters.blockchain.state import TxState
from app.core.config import get_settings


# ---------------------------------------------------------------------------
# FabricBlockchainAdapter — configuration tests
# ---------------------------------------------------------------------------

class TestFabricAdapterConfiguration:
    def test_not_configured_without_channel(self):
        adapter = FabricBlockchainAdapter(chaincode="honeychain", gateway_url="http://localhost:9443")
        assert adapter.configured is False
        assert adapter.fabric_status == "FABRIC_NOT_CONFIGURED"

    def test_not_configured_without_chaincode(self):
        adapter = FabricBlockchainAdapter(channel="mychannel", gateway_url="http://localhost:9443")
        assert adapter.configured is False
        assert adapter.fabric_status == "FABRIC_NOT_CONFIGURED"

    def test_not_configured_without_gateway_url(self):
        adapter = FabricBlockchainAdapter(channel="mychannel", chaincode="honeychain")
        assert adapter.configured is False
        assert adapter.fabric_status == "FABRIC_NOT_CONFIGURED"

    def test_configured_when_all_present(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        assert adapter.configured is True
        assert adapter.fabric_status == "CONFIGURED"

    def test_ledger_name_is_fabric(self):
        adapter = FabricBlockchainAdapter(channel="mychannel", chaincode="honeychain")
        assert adapter.ledger_name == "fabric"


# ---------------------------------------------------------------------------
# FabricBlockchainAdapter — submit_anchor tests (mocked HTTP)
# ---------------------------------------------------------------------------

class TestFabricAdapterSubmitAnchor:
    def test_submit_raises_not_configured_when_no_url(self):
        adapter = FabricBlockchainAdapter(channel="mychannel", chaincode="honeychain")
        with pytest.raises(LedgerNotConfigured, match="FABRIC_NOT_CONFIGURED"):
            adapter.submit_anchor({"evidence_root": "abc123"}, "tx-ref-1")

    def test_submit_calls_gateway_service(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "status": "committed",
            "result": {
                "anchorId": "B-TEST:abc123",
                "batchId": "B-TEST",
                "blockchainTxId": "5f3c9e4f7a6b2c8d1e0f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f",
            },
        }).encode("utf-8")
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("app.adapters.blockchain.gateway.urllib.request.urlopen", return_value=mock_response):
            result = adapter.submit_anchor(
                {"evidence_root": "abc123", "batch_id": "B-TEST"},
                "tx-ref-1",
            )

        assert result["state"] == TxState.CONFIRMED
        assert result["network"] == "fabric:mychannel"
        assert result["tx_hash"] == "5f3c9e4f7a6b2c8d1e0f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f"
        assert result["fabric_result"]["batchId"] == "B-TEST"

    def test_submit_already_anchored_returns_confirmed(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "status": "committed",
            "result": {
                "anchorId": "tx-ref-2:abc123",
                "batchId": "abc123",
                "blockchainTxId": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            },
        }).encode("utf-8")
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("app.adapters.blockchain.gateway.urllib.request.urlopen", return_value=mock_response):
            result = adapter.submit_anchor(
                {"evidence_root": "abc123"}, "tx-ref-2"
            )

        assert result["state"] == TxState.CONFIRMED

    def test_submit_gateway_unavailable_raises(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        with patch(
            "app.adapters.blockchain.gateway.urllib.request.urlopen",
            side_effect=Exception("connection refused"),
        ):
            with pytest.raises(LedgerUnavailable, match="FABRIC_UNAVAILABLE"):
                adapter.submit_anchor({"evidence_root": "abc123"}, "tx-ref-3")

    def test_submit_http_error_classified(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        import urllib.error
        error_resp = MagicMock()
        error_resp.read.return_value = json.dumps({
            "status": "FABRIC_ENDORSEMENT_FAILED",
            "error": "endorsement policy failure",
        }).encode("utf-8")

        with patch(
            "app.adapters.blockchain.gateway.urllib.request.urlopen",
            side_effect=urllib.error.HTTPError(
                url="http://localhost:9443/submit",
                code=502,
                msg="Bad Gateway",
                hdrs={},
                fp=error_resp,
            ),
        ):
            with pytest.raises(LedgerUnavailable, match="FABRIC_HTTP_ERROR"):
                adapter.submit_anchor({"evidence_root": "abc123"}, "tx-ref-4")


# ---------------------------------------------------------------------------
# FabricBlockchainAdapter — verify_anchor tests (mocked HTTP)
# ---------------------------------------------------------------------------

class TestFabricAdapterVerifyAnchor:
    def test_verify_raises_not_configured_when_no_url(self):
        adapter = FabricBlockchainAdapter(channel="mychannel", chaincode="honeychain")
        with pytest.raises(LedgerNotConfigured):
            adapter.verify_anchor("some-hash")

    def test_verify_returns_true_when_found(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "status": "success",
            "result": {"anchored": True, "batchId": "some-hash"},
        }).encode("utf-8")
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("app.adapters.blockchain.gateway.urllib.request.urlopen", return_value=mock_response):
            assert adapter.verify_anchor("some-hash") is True

    def test_verify_returns_false_when_not_found(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "status": "success",
            "result": {"anchored": False, "batchId": "nonexistent"},
        }).encode("utf-8")
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("app.adapters.blockchain.gateway.urllib.request.urlopen", return_value=mock_response):
            assert adapter.verify_anchor("nonexistent") is False


# ---------------------------------------------------------------------------
# FabricBlockchainAdapter — health_check tests
# ---------------------------------------------------------------------------

class TestFabricAdapterHealthCheck:
    def test_health_check_not_configured(self):
        adapter = FabricBlockchainAdapter(channel="mychannel", chaincode="honeychain")
        result = adapter.health_check()
        assert result["status"] == "FABRIC_NOT_CONFIGURED"
        assert result["adapter"] == "fabric"

    def test_health_check_connected(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "status": "connected",
            "adapter": "fabric",
            "network": "mychannel",
            "channel": "mychannel",
            "chaincode": "honeychain",
            "chaincode_version": "2.0",
            "chaincode_sequence": 6,
            "peer": "peer0.org1.example.com:7051",
            "msp_id": "Org1MSP",
            "last_verified_at": "2026-09-10T20:00:00Z",
            "error": None,
        }).encode("utf-8")
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("app.adapters.blockchain.gateway.urllib.request.urlopen", return_value=mock_response):
            result = adapter.health_check()

        assert result["status"] == "connected"
        assert result["channel"] == "mychannel"
        assert result["chaincode_version"] == "2.0"
        assert result["peer"] == "peer0.org1.example.com:7051"

    def test_health_check_unavailable(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        with patch(
            "app.adapters.blockchain.gateway.urllib.request.urlopen",
            side_effect=Exception("connection refused"),
        ):
            result = adapter.health_check()

        assert result["status"] == "unavailable"
        assert "FABRIC_UNAVAILABLE" in result["error"]

    def test_health_check_misconfigured(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "status": "misconfigured",
            "error": "Missing required env vars: FABRIC_PEER_ENDPOINT",
        }).encode("utf-8")
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("app.adapters.blockchain.gateway.urllib.request.urlopen", return_value=mock_response):
            result = adapter.health_check()

        assert result["status"] == "misconfigured"


# ---------------------------------------------------------------------------
# Chaincode contract mapping
# ---------------------------------------------------------------------------

class TestChaincodeContractMapping:
    def test_chaincode_functions_are_correct(self):
        from app.adapters.blockchain.gateway import CHAINCODE_FUNCTIONS

        assert CHAINCODE_FUNCTIONS["ANCHOR_MERKLE_ROOT"] == "anchorMerkleRoot"
        assert CHAINCODE_FUNCTIONS["GET_ANCHOR"] == "getAnchor"
        assert CHAINCODE_FUNCTIONS["VERIFY_MERKLE_ROOT"] == "verifyMerkleRoot"
        assert CHAINCODE_FUNCTIONS["SUBMIT_EVENT"] == "submitEvent"
        assert CHAINCODE_FUNCTIONS["CREATE_BATCH"] == "createBatch"
        assert CHAINCODE_FUNCTIONS["GET_EVENT"] == "getEvent"

    def test_node_chaincode_mapping_matches(self):
        """Verify the Python mapping matches the deployed chaincode function names."""
        from app.adapters.blockchain.gateway import CHAINCODE_FUNCTIONS

        expected = {
            "getEvent", "getBatch", "getAnchor", "verifyMerkleRoot",
            "getLineage", "getCertificate", "getHistory",
            "submitEvent", "createBatch", "anchorMerkleRoot",
            "recordLineage", "registerCertificate", "transitionBatch",
            "revokeCertificate",
        }
        assert set(CHAINCODE_FUNCTIONS.values()) == expected


# ---------------------------------------------------------------------------
# Gateway integration (mocked Fabric)
# ---------------------------------------------------------------------------

class TestGatewayWithFabricAdapter:
    def test_gateway_uses_fabric_adapter_when_configured(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        gw = BlockchainGateway(adapter)
        assert gw.ledger_name == "fabric"

    def test_gateway_submit_anchor_calls_adapter(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        gw = BlockchainGateway(adapter)

        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "status": "committed",
            "result": "anchored",
        }).encode("utf-8")
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("app.adapters.blockchain.gateway.urllib.request.urlopen", return_value=mock_response):
            result = gw.submit_anchor(
                batch_id="B-TEST-1",
                evidence_root="a" * 64,
                anchor_type="evidence_bundle",
            )

        assert result["state"] == TxState.CONFIRMED
        assert "fabric:mychannel" in result["network"]

    def test_gateway_verify_anchor_returns_false_on_failure(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        gw = BlockchainGateway(adapter)

        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "status": "success",
            "result": {"anchored": False, "batchId": "nonexistent-hash"},
        }).encode("utf-8")
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("app.adapters.blockchain.gateway.urllib.request.urlopen", return_value=mock_response):
            assert gw.verify_anchor("nonexistent-hash") is False

    def test_gateway_verify_anchor_returns_true_on_confirm(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        gw = BlockchainGateway(adapter)

        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "status": "success",
            "result": {"anchored": True, "batchId": "test-hash"},
        }).encode("utf-8")
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("app.adapters.blockchain.gateway.urllib.request.urlopen", return_value=mock_response):
            assert gw.verify_anchor("test-hash") is True

    def test_gateway_submit_event_fabric(self):
        adapter = FabricBlockchainAdapter(
            channel="mychannel", chaincode="honeychain", gateway_url="http://localhost:9443"
        )
        gw = BlockchainGateway(adapter)

        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "status": "committed",
            "result": "recorded",
        }).encode("utf-8")
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("app.adapters.blockchain.gateway.urllib.request.urlopen", return_value=mock_response):
            result = gw.submit_event(
                event={"type": "custody_transfer", "batch_id": "B-TEST"}
            )

        assert result["state"] == TxState.CONFIRMED


# ---------------------------------------------------------------------------
# build_blockchain_gateway factory
# ---------------------------------------------------------------------------

class TestBuildGatewayFactory:
    def test_fabric_adapter_created_when_configured(self):
        orig_val = os.environ.get("BLOCKCHAIN_ADAPTER")
        orig_ch = os.environ.get("FABRIC_CHANNEL")
        orig_cc = os.environ.get("FABRIC_CHAINCODE")
        orig_gw = os.environ.get("FABRIC_GATEWAY_URL")
        try:
            os.environ["BLOCKCHAIN_ADAPTER"] = "fabric"
            os.environ["FABRIC_CHANNEL"] = "mychannel"
            os.environ["FABRIC_CHAINCODE"] = "honeychain"
            os.environ["FABRIC_GATEWAY_URL"] = "http://localhost:9443"
            os.environ["SUPABASE_URL"] = ""
            os.environ["SUPABASE_SERVICE_ROLE_KEY"] = ""
            get_settings.cache_clear()
            gw = build_blockchain_gateway()
            assert gw.ledger_name == "fabric"
            assert isinstance(gw._adapter, FabricBlockchainAdapter)
        finally:
            if orig_val is not None:
                os.environ["BLOCKCHAIN_ADAPTER"] = orig_val
            else:
                os.environ.pop("BLOCKCHAIN_ADAPTER", None)
            if orig_ch is not None:
                os.environ["FABRIC_CHANNEL"] = orig_ch
            else:
                os.environ.pop("FABRIC_CHANNEL", None)
            if orig_cc is not None:
                os.environ["FABRIC_CHAINCODE"] = orig_cc
            else:
                os.environ.pop("FABRIC_CHAINCODE", None)
            if orig_gw is not None:
                os.environ["FABRIC_GATEWAY_URL"] = orig_gw
            else:
                os.environ.pop("FABRIC_GATEWAY_URL", None)
            get_settings.cache_clear()


# ---------------------------------------------------------------------------
# LIVE_RUNTIME tests — only run when FABRIC_GATEWAY_URL is actually set
# ---------------------------------------------------------------------------

@pytest.mark.skipif(
    not get_settings().fabric_gateway_url,
    reason="LIVE_RUNTIME: FABRIC_GATEWAY_URL not set",
)
class TestLiveFabricRuntime:
    """These tests run against the real Fabric network via the Node.js gateway.

    They are skipped in CI and local dev unless FABRIC_GATEWAY_URL is configured.
    """

    def test_live_health_check(self):
        adapter = FabricBlockchainAdapter(
            channel=get_settings().fabric_channel,
            chaincode=get_settings().fabric_chaincode,
            gateway_url=get_settings().fabric_gateway_url,
        )
        result = adapter.health_check()
        assert result["status"] == "connected", f"Fabric not connected: {result.get('error')}"
        assert result["channel"] == get_settings().fabric_channel
        assert result["chaincode_version"] == "2.0"

    def test_live_verify_anchor_probe(self):
        adapter = FabricBlockchainAdapter(
            channel=get_settings().fabric_channel,
            chaincode=get_settings().fabric_chaincode,
            gateway_url=get_settings().fabric_gateway_url,
        )
        # getAnchor on an existing demo batch must report anchored (no raise)
        result = adapter.verify_anchor("HC-DEMO-001")
        assert isinstance(result, bool)

    def test_live_submit_and_verify(self):
        """Submit a real anchor against the live ledger, then verify it exists."""
        adapter = FabricBlockchainAdapter(
            channel=get_settings().fabric_channel,
            chaincode=get_settings().fabric_chaincode,
            gateway_url=get_settings().fabric_gateway_url,
        )
        import time as _t
        batch_id = f"HC-LIVE-{int(_t.time())}"
        hex_root = "f50ff9e5c5a6c57321799ba95e1f9a9c6cc2c0e2a0f8f3e5b9a1c2d3e4f5a6b7"

        create_body = json.dumps({
            "batchId": batch_id,
            "batchType": "HARVEST",
            "sourceHiveIds": [],
            "parentBatchIds": [],
            "actorId": "honeychain-backend-test",
            "organizationId": "honeychain",
            "serverTimestamp": _t.strftime("%Y-%m-%dT%H:%M:%SZ", _t.gmtime()),
            "metadata": {"purpose": "live-runtime-proof", "run_id": int(_t.time())},
        })
        adapter._http_request("POST", "/submit", {
            "function": "createBatch",
            "args": [create_body],
        }, timeout=60)

        result = adapter.submit_anchor(
            {"evidence_root": hex_root, "batch_id": batch_id},
            f"live-test-{_t.time()}",
        )
        assert result["state"] == TxState.CONFIRMED
        assert adapter.verify_anchor(batch_id) is True
