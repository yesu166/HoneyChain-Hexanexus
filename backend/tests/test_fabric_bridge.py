"""Tests for the HoneyChain Fabric bridge.

Covers the security boundary between the public API (Render) and the Fabric host
(EC2), and pins the honest-failure contract: the bridge must never degrade to
the local development ledger, and it must never report a transaction that did
not happen.

Caddy enforces the path allowlist, so these tests cover the two layers above it:
the authenticated `/internal/fabric/*` router and the `RemoteFabricAdapter` that
calls it.
"""
from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
from fastapi.testclient import TestClient

from app.adapters.blockchain.bridge import RemoteFabricAdapter
from app.adapters.blockchain.gateway import LedgerUnavailable
from app.main import app

TOKEN = "bridge-test-secret"
BRIDGE_ENV = "FABRIC_BRIDGE_TOKEN"


# ---------------------------------------------------------------------------
# Internal router: authentication
# ---------------------------------------------------------------------------


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv(BRIDGE_ENV, TOKEN)
    return TestClient(app)


def test_health_requires_credential(client):
    assert client.get("/internal/fabric/health").status_code == 401


def test_health_rejects_wrong_credential(client):
    r = client.get(
        "/internal/fabric/health", headers={"Authorization": "Bearer wrong-secret"}
    )
    assert r.status_code == 401
    # The response must not leak the expected secret.
    assert TOKEN not in r.text


def test_health_rejects_valid_token_as_prefix(client):
    """compare_digest must reject a correct-prefix guess, not accept it."""
    r = client.get(
        "/internal/fabric/health",
        headers={"Authorization": f"Bearer {TOKEN[:-1]}"},
    )
    assert r.status_code == 401


def test_health_rejects_non_bearer_scheme(client):
    r = client.get("/internal/fabric/health", headers={"Authorization": TOKEN})
    assert r.status_code == 401


def test_bridge_refuses_when_secret_unset(monkeypatch):
    """An unset secret must close the endpoint, not open it."""
    monkeypatch.delenv(BRIDGE_ENV, raising=False)
    r = TestClient(app).get(
        "/internal/fabric/health", headers={"Authorization": f"Bearer {TOKEN}"}
    )
    assert r.status_code == 503


def test_bridge_refuses_non_fabric_adapter(client):
    """A host without the Fabric adapter must not serve the bridge.

    This is the guard that stops the bridge from silently answering with the
    local development ledger.
    """
    r = client.get("/internal/fabric/health", headers={"Authorization": f"Bearer {TOKEN}"})
    assert r.status_code == 503
    assert "Fabric adapter is not active" in r.text


def test_query_rejects_unknown_op(client):
    r = client.post(
        "/internal/fabric/query",
        json={"op": "drop_everything", "ref": "x"},
        headers={"Authorization": f"Bearer {TOKEN}"},
    )
    assert r.status_code in (401, 404)


# ---------------------------------------------------------------------------
# RemoteFabricAdapter: transport + honest failure states
# ---------------------------------------------------------------------------


class _BridgeHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    mode = "ok"

    def log_message(self, *args):  # silence test output
        pass

    def _authed(self) -> bool:
        return self.headers.get("Authorization") == f"Bearer {TOKEN}"

    def _reply(self, code: int, obj: dict) -> None:
        raw = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if type(self).mode == "hang":
            threading.Event().wait(30)
            return
        if not self._authed():
            return self._reply(401, {"detail": "Invalid service credential"})
        self._reply(
            200,
            {
                "status": "FABRIC_CONNECTED",
                "channel": "mychannel",
                "chaincode": "honeychain",
                "chaincode_version": "2.0",
                "chaincode_sequence": 6,
                "peer": "localhost:7051",
                "msp_id": "Org1MSP",
            },
        )

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        # Authentication is checked before anything else, as a real service
        # would do, so an unauthenticated caller never reaches business logic.
        if not self._authed():
            return self._reply(401, {"detail": "Invalid service credential"})
        if type(self).mode == "no_txid":
            return self._reply(200, {"network": "fabric:mychannel"})
        if self.path.endswith("/anchor"):
            return self._reply(
                200,
                {
                    "tx_hash": f"a1b2c3d4{body.get('tx_ref', '')}",
                    "network": "fabric:mychannel",
                    "state": "CONFIRMED",
                    "block_number": "7",
                },
            )
        if body.get("op") == "verify_anchor":
            return self._reply(200, {"verified": str(body.get("ref", "")).startswith("HC")})
        return self._reply(200, {"state": "CONFIRMED", "block_number": "7"})


@pytest.fixture
def bridge_url():
    # Reset the handler mode so state cannot leak between tests.
    _BridgeHandler.mode = "ok"
    server = ThreadingHTTPServer(("127.0.0.1", 0), _BridgeHandler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{server.server_address[1]}"
    server.shutdown()


@pytest.fixture
def adapter(bridge_url):
    _BridgeHandler.mode = "ok"
    return RemoteFabricAdapter(
        bridge_url=bridge_url,
        service_token=TOKEN,
        channel="mychannel",
        chaincode="honeychain",
    )


def test_health_passes_through_real_chain_facts(adapter):
    health = adapter.health_check()
    assert health["adapter"] == "fabric"
    assert health["status"] == "FABRIC_CONNECTED"
    assert health["chaincode_sequence"] == 6
    assert health["msp_id"] == "Org1MSP"


def test_anchor_returns_real_transaction_id(adapter):
    receipt = adapter.submit_anchor({"evidence_hash": "deadbeef"}, "HC-TEST-1")
    assert receipt["tx_hash"].startswith("a1b2c3d4")
    assert receipt["state"] == "CONFIRMED"
    assert receipt["network"] == "fabric:mychannel"


def test_anchor_without_tx_id_raises_instead_of_faking(adapter):
    """A success with no transaction id must never become a 'verified' anchor."""
    _BridgeHandler.mode = "no_txid"
    with pytest.raises(LedgerUnavailable, match="no transaction id"):
        adapter.submit_anchor({"evidence_hash": "x"}, "HC-TEST-1")


def test_anchor_with_wrong_token_reports_auth_failure(bridge_url):
    bad = RemoteFabricAdapter(bridge_url=bridge_url, service_token="wrong")
    with pytest.raises(LedgerUnavailable, match="FABRIC_AUTH_FAILED"):
        bad.submit_anchor({"x": 1}, "t")


def test_health_with_wrong_token_reports_auth_failure(bridge_url):
    bad = RemoteFabricAdapter(bridge_url=bridge_url, service_token="wrong")
    assert bad.health_check()["status"] == "FABRIC_AUTH_FAILED"


def test_unreachable_bridge_reports_unavailable(adapter):
    dead = RemoteFabricAdapter(bridge_url="http://127.0.0.1:1", service_token=TOKEN)
    assert dead.health_check()["status"] == "FABRIC_UNAVAILABLE"


def test_slow_bridge_reports_timeout(adapter):
    _BridgeHandler.mode = "hang"
    assert adapter.health_check()["status"] == "FABRIC_TIMEOUT"


def test_unconfigured_bridge_never_claims_fabric():
    unconfigured = RemoteFabricAdapter()
    assert unconfigured.configured is False
    assert unconfigured.fabric_status == "FABRIC_NOT_CONFIGURED"
    assert unconfigured.health_check()["status"] == "FABRIC_NOT_CONFIGURED"


def test_missing_token_is_never_fabric_ready(bridge_url):
    """A URL without a secret must not be treated as configured."""
    tokenless = RemoteFabricAdapter(bridge_url=bridge_url)
    assert tokenless.configured is False
    assert tokenless.fabric_status == "FABRIC_NOT_CONFIGURED"


def test_verify_anchor_is_delegated(adapter):
    assert adapter.verify_anchor("HC-E2E-1") is True
    assert adapter.verify_anchor("not-a-batch") is False
    assert adapter.verify_anchor("") is False


def test_adapter_is_labelled_fabric(adapter):
    """The chain really is Fabric, so the honest ledger label is preserved."""
    assert adapter.ledger_name == "fabric"
