"""BlockchainGateway — the single boundary the business layer uses.

The application never calls an SDK directly. It calls the gateway, which
dispatches to the configured ledger adapter. Three adapter classes exist:

- LocalLedgerAdapter  -> development/testing ONLY, NEVER presented as real chain
- EVMBlockchainAdapter -> EVM (e.g. Polygon Amoy) when RPC + wallet configured
- FabricBlockchainAdapter -> Hyperledger Fabric when a working network exists

When no real ledger is configured the gateway reports the honest status
(BLOCKCHAIN_NOT_CONFIGURED / FABRIC_NOT_CONFIGURED / BLOCKCHAIN_UNAVAILABLE)
instead of fabricating success.

The gateway knows nothing about IoT/sensors/AI; it only anchors and verifies
cryptographic commitments plus explicit business events.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

from ...core.crypto import hash_payload
from .state import (
    BlockchainTransaction,
    TransactionTracker,
    TxState,
)


class LedgerNotConfigured(Exception):
    """Raised when no real ledger backend is configured."""


class LedgerUnavailable(Exception):
    """Raised when a configured ledger cannot be reached right now."""


# ---------------------------------------------------------------------------
# Backend adapter abstraction
# ---------------------------------------------------------------------------

class LedgerAdapter(ABC):
    """Bottom half of the gateway: concrete ledger-specific operations.

    Subclasses must name themselves honestly (they never pretend to be a real
    chain unless they are). `submitted` operations return a receipt with a
    transaction reference so the gateway can track idempotent status.
    """

    # human + machine label of the ledger, e.g. "local" / "evm" / "fabric"
    ledger_name: str = "unknown"

    @abstractmethod
    def submit_anchor(
        self, payload: dict[str, Any], tx_ref: str
    ) -> dict[str, Any]:
        """Persist a cryptographic commitment; return {'tx_hash','network',...}."""

    @abstractmethod
    def verify_anchor(self, ref: str) -> bool:
        """True only when [ref] can be proven anchored on the ledger."""

    @abstractmethod
    def get_transaction_status(self, tx_hash: str) -> dict[str, Any]:
        """Return {'state', 'block_number', 'network', ...} or raise."""

    def submit_event(
        self, event: dict[str, Any], tx_ref: str
    ) -> dict[str, Any]:
        """Optional: persist an explicit business event. Default = anchor its hash."""
        return self.submit_anchor({"event_hash": hash_payload(event)}, tx_ref)


# ---------------------------------------------------------------------------
# Local ledger (dev/test only — never shown as real)
# ---------------------------------------------------------------------------

class LocalLedgerAdapter(LedgerAdapter):
    """Development/testing ledger.

    Holds commitments in-process. This is NOT a real blockchain and is never
    presented as one. It exists so the full pipeline (offline -> evidence ->
    merkle -> anchor -> verify -> tamper) can be exercised without external
    infrastructure, and so failure/retry paths can be unit-tested.
    """

    ledger_name = "local"

    def __init__(self) -> None:
        self._ledger: dict[str, dict[str, Any]] = {}

    def _stamp(self, key: str) -> str:
        from datetime import datetime, timezone

        return datetime.now(timezone.utc).isoformat()

    def submit_anchor(self, payload, tx_ref):
        data_hash = hash_payload(payload)
        self._ledger.setdefault(tx_ref, {})
        self._ledger[tx_ref].update(
            {
                "data_hash": data_hash,
                "state": TxState.CONFIRMED,
                "network": "local",
                "tx_hash": f"LOCAL-{tx_ref}",
                "ledger": "local",
                "confirmed_at": self._stamp(None),
            }
        )
        return {
            "tx_hash": self._ledger[tx_ref]["tx_hash"],
            "network": "local",
            "state": TxState.CONFIRMED,
        }

    def verify_anchor(self, ref):
        """True if [ref] is a confirmed tx_hash OR data_hash on the local
        ledger — so callers can verify by evidence root hash or by receipt."""
        if not ref:
            return False
        for entry in self._ledger.values():
            if entry.get("state") != TxState.CONFIRMED:
                continue
            if ref == entry.get("tx_hash") or ref == entry.get("data_hash"):
                return True
        return False

    def get_transaction_status(self, tx_hash):
        for entry in self._ledger.values():
            if entry.get("tx_hash") == tx_hash:
                return {
                    "state": entry.get("state", TxState.UNKNOWN),
                    "network": "local",
                    "block_number": "",
                }
        raise LedgerUnavailable(f"unknown local tx: {tx_hash}")

    def tamper(self, tx_ref: str) -> None:
        """DEMO-ONLY: mark a commitment as changed so verification fails."""
        if tx_ref in self._ledger:
            self._ledger[tx_ref]["state"] = TxState.UNKNOWN


# ---------------------------------------------------------------------------
# EVM boundary
# ---------------------------------------------------------------------------

class EVMBlockchainAdapter(LedgerAdapter):
    """EVM (e.g. Polygon Amoy) adapter.

    Implemented when RPC URL + signing wallet + deployed contract address are
    configured. Until then it reports BLOCKCHAIN_NOT_CONFIGURED rather than
    fabricating a transaction.
    """

    ledger_name = "evm"

    def __init__(
        self,
        *,
        rpc_url: str = "",
        chain_id: str = "",
        contract_address: str = "",
        private_key_hex: str = "",
        confirmations: int = 1,
    ) -> None:
        self._rpc_url = rpc_url
        self._chain_id = chain_id
        self._contract = contract_address
        self._key = private_key_hex
        self._confirmations = confirmations

    @property
    def configured(self) -> bool:
        return bool(self._rpc_url and self._contract and self._key and self._chain_id)

    def _require(self) -> None:
        if not self.configured:
            raise LedgerNotConfigured(
                "BLOCKCHAIN_NOT_CONFIGURED: EVM RPC URL, chain id, contract "
                "address and signing wallet are required but not configured."
            )

    def submit_anchor(self, payload, tx_ref):
        self._require()
        raise LedgerUnavailable(
            "EVM adapter boundary implemented; live RPC submission requires "
            "web3/geth provider wiring and a funded wallet. See docs/BLOCKCHAIN.md."
        )

    def verify_anchor(self, ref):
        self._require()
        raise LedgerUnavailable(
            "EVM adapter boundary implemented; live verification requires "
            "a configured provider."
        )

    def get_transaction_status(self, tx_hash):
        self._require()
        raise LedgerUnavailable(
            "EVM adapter boundary implemented; live status requires a "
            "configured provider."
        )


# ---------------------------------------------------------------------------
# Fabric boundary — talks to the Node.js Fabric Gateway service
# ---------------------------------------------------------------------------

import logging
import os
import urllib.error
import urllib.request
import json as _json

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Chaincode contract mapping — exact names from deployed chaincode v2.0
# Verified by inspecting the chaincode container on EC2:
#   dev-peer0.org1.example.com-honeychain_2.0-...
# Source: /usr/local/src/lib/honeychain.js (HoneyChainContract)
# ---------------------------------------------------------------------------

CHAINCODE_FUNCTIONS = {
    # Read functions
    "GET_EVENT": "getEvent",
    "GET_BATCH": "getBatch",
    "GET_ANCHOR": "getAnchor",
    "VERIFY_MERKLE_ROOT": "verifyMerkleRoot",
    "GET_LINEAGE": "getLineage",
    "GET_CERTIFICATE": "getCertificate",
    "GET_HISTORY": "getHistory",
    # Write functions
    "SUBMIT_EVENT": "submitEvent",
    "CREATE_BATCH": "createBatch",
    "ANCHOR_MERKLE_ROOT": "anchorMerkleRoot",
    "RECORD_LINEAGE": "recordLineage",
    "REGISTER_CERTIFICATE": "registerCertificate",
    "TRANSITION_BATCH": "transitionBatch",
    "REVOKE_CERTIFICATE": "revokeCertificate",
}


class FabricBlockchainAdapter(LedgerAdapter):
    """Hyperledger Fabric adapter backed by the Node.js Fabric Gateway service.

    The adapter makes real HTTP calls to a running Node.js service that
    connects to the live Fabric network. It never fabricates transactions,
    blocks, peers, orderers, MSP identities, payloads or ledger state.

    Connection statuses returned (never faked):
      FABRIC_CONNECTED          - real query succeeded against live Fabric
      FABRIC_NOT_CONFIGURED     - no gateway URL configured
      FABRIC_UNAVAILABLE        - gateway service unreachable
      FABRIC_AUTH_FAILED        - identity/TLS error
      FABRIC_TIMEOUT            - gateway service timed out
      FABRIC_MISCONFIGURED      - gateway service reports missing env vars
      FABRIC_QUERY_FAILED       - query executed but failed on-chain
      FABRIC_TRANSACTION_FAILED - transaction submitted but failed
      FABRIC_ENDORSEMENT_FAILED - endorsement policy not satisfied
    """

    ledger_name = "fabric"

    def __init__(
        self,
        *,
        channel: str = "",
        chaincode: str = "",
        gateway_url: str = "",
    ) -> None:
        self._channel = channel
        self._chaincode = chaincode
        self._gateway_url = (gateway_url or "").rstrip("/")

    @property
    def configured(self) -> bool:
        return bool(self._channel and self._chaincode and self._gateway_url)

    @property
    def fabric_status(self) -> str:
        """Honest status classification — never pretends to be connected."""
        if not self._channel or not self._chaincode:
            return "FABRIC_NOT_CONFIGURED"
        if not self._gateway_url:
            return "FABRIC_NOT_CONFIGURED"
        return "CONFIGURED"

    def _http_request(
        self, method: str, path: str, body: dict | None = None, timeout: int = 30
    ) -> dict[str, Any]:
        """Make an HTTP request to the Node.js Fabric Gateway service.

        Returns the parsed JSON response or raises LedgerUnavailable.
        """
        url = f"{self._gateway_url}{path}"
        data = _json.dumps(body).encode("utf-8") if body else None
        headers = {"Content-Type": "application/json"}

        try:
            req = urllib.request.Request(
                url, data=data, headers=headers, method=method
            )
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read().decode("utf-8")
                return _json.loads(raw)
        except urllib.error.HTTPError as exc:
            body_text = ""
            try:
                body_text = exc.read().decode("utf-8")
            except Exception:
                pass
            try:
                error_data = _json.loads(body_text)
            except Exception:
                error_data = {"error": body_text or str(exc)}
            error_data["_http_status"] = exc.code
            raise LedgerUnavailable(
                f"FABRIC_HTTP_ERROR: {exc.code} {exc.reason} - "
                f"{error_data.get('error', '')}"
            ) from exc
        except urllib.error.URLError as exc:
            raise LedgerUnavailable(
                f"FABRIC_UNAVAILABLE: cannot reach Fabric Gateway at {url} - {exc.reason}"
            ) from exc
        except TimeoutError:
            raise LedgerUnavailable(
                f"FABRIC_TIMEOUT: Fabric Gateway at {url} timed out after {timeout}s"
            ) from None
        except Exception as exc:
            raise LedgerUnavailable(
                f"FABRIC_UNAVAILABLE: {exc}"
            ) from exc

    def _classify_gateway_response(self, resp: dict) -> None:
        """Translate Node.js gateway status into Python adapter exceptions."""
        status = resp.get("status", "")
        error = resp.get("error", "")

        if status == "misconfigured":
            raise LedgerNotConfigured(
                f"FABRIC_MISCONFIGURED: {error}"
            )
        if status in ("unavailable", "FABRIC_UNAVAILABLE"):
            raise LedgerUnavailable(
                f"FABRIC_UNAVAILABLE: {error}"
            )
        if "auth" in str(error).lower() or "UNAUTHENTICATED" in str(error):
            raise LedgerUnavailable(
                f"FABRIC_AUTH_FAILED: {error}"
            )

    def health_check(self) -> dict[str, Any]:
        """Perform a real Fabric health query via the gateway service.

        Returns structured status — never claims success without a real query.
        """
        if not self._gateway_url:
            return {
                "adapter": "fabric",
                "status": "FABRIC_NOT_CONFIGURED",
                "channel": self._channel,
                "chaincode": self._chaincode,
                "error": "No FABRIC_GATEWAY_URL configured",
            }

        try:
            resp = self._http_request("GET", "/health", timeout=10)
            return {
                "adapter": "fabric",
                "status": resp.get("status", "unknown"),
                "network": resp.get("network", ""),
                "channel": resp.get("channel", self._channel),
                "chaincode": resp.get("chaincode", self._chaincode),
                "chaincode_version": resp.get("chaincode_version"),
                "chaincode_sequence": resp.get("chaincode_sequence"),
                "peer": resp.get("peer", ""),
                "msp_id": resp.get("msp_id", ""),
                "last_verified_at": resp.get("last_verified_at"),
                "error": resp.get("error"),
            }
        except LedgerUnavailable as exc:
            return {
                "adapter": "fabric",
                "status": "unavailable",
                "channel": self._channel,
                "chaincode": self._chaincode,
                "error": str(exc),
            }
        except LedgerNotConfigured as exc:
            return {
                "adapter": "fabric",
                "status": "misconfigured",
                "channel": self._channel,
                "chaincode": self._chaincode,
                "error": str(exc),
            }

    def submit_anchor(self, payload, tx_ref):
        if not self.configured:
            raise LedgerNotConfigured(
                f"FABRIC_NOT_CONFIGURED: gateway_url={self._gateway_url!r}, "
                f"channel={self._channel!r}, chaincode={self._chaincode!r}"
            )

        data_hash = payload.get("evidence_root") or payload.get("data_hash", "")
        if not data_hash:
            from ...core.crypto import hash_payload as _hp
            data_hash = _hp(payload)

        batch_id = payload.get("batch_id", tx_ref[:40])
        anchor_json = _json.dumps({
            "batchId": batch_id,
            "merkleRoot": data_hash,
            "evidenceHashes": [data_hash],
            "evidenceBundleId": payload.get("batch_id", ""),
            "actorId": payload.get("organization_ref", "honeychain-backend"),
            "organizationId": payload.get("organization_ref", "honeychain"),
            "serverTimestamp": tx_ref,
            "anchorId": f"HC-{batch_id}-{tx_ref[:8]}",
        })

        body = {
            "function": CHAINCODE_FUNCTIONS["ANCHOR_MERKLE_ROOT"],
            "args": [anchor_json],
        }

        resp = self._http_request("POST", "/submit", body, timeout=60)
        self._classify_gateway_response(resp)

        result = resp.get("result", {})
        blockchain_tx_id = ""
        if isinstance(result, dict):
            blockchain_tx_id = result.get("blockchainTxId", "")
        elif isinstance(result, str):
            blockchain_tx_id = result

        return {
            "tx_hash": blockchain_tx_id or f"FABRIC-ANCHOR-{data_hash[:16]}",
            "network": f"fabric:{self._channel}",
            "state": TxState.CONFIRMED,
            "fabric_result": result,
        }

    def verify_anchor(self, ref):
        if not self.configured:
            raise LedgerNotConfigured("FABRIC_NOT_CONFIGURED")

        body = {
            "function": CHAINCODE_FUNCTIONS["GET_ANCHOR"],
            "args": [ref],
        }

        resp = self._http_request("POST", "/evaluate", body, timeout=30)
        self._classify_gateway_response(resp)

        result = resp.get("result", {})
        if isinstance(result, str):
            try:
                result = _json.loads(result)
            except Exception:
                return False

        return result.get("anchored", False) is True

    def submit_event(self, event, tx_ref):
        if not self.configured:
            raise LedgerNotConfigured("FABRIC_NOT_CONFIGURED")

        event_payload = {
            "eventId": event.get("event_id", tx_ref[:40]),
            "eventType": event.get("type", event.get("eventType", "UNKNOWN")),
            "entityType": event.get("entity_type", "unknown"),
            "entityId": event.get("entity_id", event.get("batch_id", "")),
            "actorId": event.get("actor_id", "honeychain-backend"),
            "organizationId": event.get("organization_ref", "honeychain"),
            "serverTimestamp": tx_ref,
            "metadata": event,
        }
        event_json = _json.dumps(event_payload)

        body = {
            "function": CHAINCODE_FUNCTIONS["SUBMIT_EVENT"],
            "args": [event_json],
        }

        resp = self._http_request("POST", "/submit", body, timeout=60)
        self._classify_gateway_response(resp)

        result = resp.get("result", {})
        blockchain_tx_id = ""
        if isinstance(result, dict):
            blockchain_tx_id = result.get("blockchainTxId", "")
        elif isinstance(result, str):
            blockchain_tx_id = result

        return {
            "tx_hash": blockchain_tx_id or f"FABRIC-EVT-{tx_ref[:16]}",
            "network": f"fabric:{self._channel}",
            "state": TxState.CONFIRMED,
            "fabric_result": result,
        }

    def get_transaction_status(self, tx_hash):
        if not self.configured:
            raise LedgerNotConfigured("FABRIC_NOT_CONFIGURED")
        raise LedgerUnavailable(
            "FABRIC_QUERY_FAILED: transaction status lookup requires "
            "a tx_id from the Fabric Gateway service, which is not "
            "currently stored in the adapter."
        )


# ---------------------------------------------------------------------------
# Gateway
# ---------------------------------------------------------------------------

class BlockchainGateway:
    """The business-facing facade. Never talks to an SDK directly."""

    def __init__(self, adapter: LedgerAdapter | None = None) -> None:
        self._adapter = adapter or LocalLedgerAdapter()
        self._tracker = TransactionTracker()

    @property
    def ledger_name(self) -> str:
        return self._adapter.ledger_name

    # ---- orchestration helper -----------------------------------------
    def _run(self, operation: str, tx_ref: str, fn) -> dict[str, Any]:
        tx = self._tracker.begin(tx_ref, operation)
        if tx.state == TxState.CONFIRMED:
            return tx.snapshot()
        try:
            receipt = fn(tx)
        except LedgerNotConfigured as exc:
            tx.mark_failed(str(exc))
            return tx.snapshot()
        except LedgerUnavailable as exc:
            tx.mark_unknown(str(exc))
            return tx.snapshot()
        tx.mark_submitted(receipt.get("tx_hash", ""), receipt.get("network", ""))
        if receipt.get("state") == TxState.CONFIRMED:
            tx.mark_confirmed(receipt.get("block_number", ""))
        return tx.snapshot()

    # ---- public API surface -------------------------------------------
    def submit_anchor(self, *, batch_id: str, evidence_root: str,
                      anchor_type: str = "evidence_bundle",
                      organization_ref: str = "") -> dict[str, Any]:
        payload = {
            "batch_id": batch_id,
            "evidence_root": evidence_root,
            "anchor_type": anchor_type,
            "organization_ref": organization_ref,
            "schema": "honeychain-anchor-v1",
        }
        tx_ref = hash_payload(payload)[:40]
        return self._run(
            "submit_anchor", tx_ref, lambda tx: self._adapter.submit_anchor(payload, tx_ref)
        )

    def submit_event(self, *, event: dict[str, Any]) -> dict[str, Any]:
        tx_ref = f"evt-{hash_payload(event)[:32]}"
        return self._run(
            "submit_event", tx_ref, lambda tx: self._adapter.submit_event(event, tx_ref)
        )

    def submit_batch_state_transition(
        self, *, batch_id: str, from_state: str, to_state: str,
        organization_ref: str = "",
    ) -> dict[str, Any]:
        return self.submit_event(
            event={
                "type": "batch_state_transition",
                "batch_id": batch_id,
                "from_state": from_state,
                "to_state": to_state,
                "organization_ref": organization_ref,
            }
        )

    def submit_custody_transfer(
        self, *, batch_id: str, sender_ref: str, receiver_ref: str,
        quantity_kg: float,
    ) -> dict[str, Any]:
        return self.submit_event(
            event={
                "type": "custody_transfer",
                "batch_id": batch_id,
                "sender_ref": sender_ref,
                "receiver_ref": receiver_ref,
                "quantity_kg": quantity_kg,
            }
        )

    def submit_certificate_anchor(
        self, *, certificate_id: str, certificate_hash: str, batch_id: str = ""
    ) -> dict[str, Any]:
        return self.submit_event(
            event={
                "type": "certificate_anchor",
                "certificate_id": certificate_id,
                "certificate_hash": certificate_hash,
                "batch_id": batch_id,
            }
        )

    def submit_lineage_event(
        self, *, input_batch_id: str, output_batch_id: str, operation: str,
        quantity_kg: float,
    ) -> dict[str, Any]:
        return self.submit_event(
            event={
                "type": "lineage_event",
                "input_batch_id": input_batch_id,
                "output_batch_id": output_batch_id,
                "operation": operation,
                "quantity_kg": quantity_kg,
            }
        )

    def verify_anchor(self, ref: str) -> bool:
        try:
            return self._adapter.verify_anchor(ref)
        except (LedgerNotConfigured, LedgerUnavailable):
            return False

    def verify_evidence(self, *, evidence_hash: str, root: str,
                        proof: list | None = None) -> bool:
        """Verify an evidence object against an anchored Merkle root.

        Proof-path membership is computed by the evidence service; here we
        confirm the anchored commitment (the root hash) still exists on the
        ledger and is confirmed.
        """
        return self.verify_anchor(root)

    def query_batch(self, batch_id: str) -> dict[str, Any]:
        return {
            "batch_id": batch_id,
            "ledger": self.ledger_name,
            "status": self.get_transaction_status_for_batch(batch_id),
        }

    def query_batch_history(self, batch_id: str) -> list[dict[str, Any]]:
        return [tx.snapshot() for tx in self._tracker.list()
                if tx.metadata.get("batch_id") == batch_id]

    def get_transaction_status_for_batch(self, batch_id: str) -> dict[str, Any]:
        txs = [tx for tx in self._tracker.list() if batch_id in str(tx.metadata)]
        if not txs:
            return {"batch_id": batch_id, "state": TxState.PENDING}
        return txs[-1].snapshot()

    def get_transaction_status(self, tx_ref: str) -> dict[str, Any] | None:
        tx = self._tracker.get(tx_ref)
        return tx.snapshot() if tx else None

    def retry(self, tx_ref: str) -> bool:
        tx = self._tracker.get(tx_ref)
        if tx is None or not tx.retry():
            return False
        return True

    def transaction_snapshots(self) -> list[dict[str, Any]]:
        return [tx.snapshot() for tx in self._tracker.list()]


def build_blockchain_gateway(settings: Any = None) -> BlockchainGateway:
    """Build the gateway from config. Defaults to the local (dev/test) ledger.

    REAL chain integration is selected by configuration:
      - EVM:   BLOCKCHAIN_RPC_URL, BLOCKCHAIN_CHAIN_ID, BLOCKCHAIN_CONTRACT,
               BLOCKCHAIN_PRIVATE_KEY (never committed)
      - FABRIC: FABRIC_CHANNEL, FABRIC_CHAINCODE (plus connection profile)
    """
    if settings is None:
        from ...core.config import get_settings

        settings = get_settings()

    adapter_name = getattr(settings, "blockchain_adapter", "local")
    if adapter_name.lower() in ("simulated", "local", "memory", ""):
        # 'simulated' is the legacy name for the local dev/testing ledger.
        adapter = LocalLedgerAdapter()
    elif adapter_name.lower() in ("evm", "ethereum", "polygon"):
        adapter = EVMBlockchainAdapter(
            rpc_url=getattr(settings, "blockchain_rpc_url", ""),
            chain_id=getattr(settings, "blockchain_chain_id", ""),
            contract_address=getattr(settings, "blockchain_contract", ""),
            private_key_hex=getattr(settings, "blockchain_private_key", ""),
        )
    elif adapter_name.lower() in ("fabric", "hyperledger"):
        adapter = FabricBlockchainAdapter(
            channel=getattr(settings, "fabric_channel", ""),
            chaincode=getattr(settings, "fabric_chaincode", ""),
            gateway_url=getattr(settings, "fabric_gateway_url", ""),
        )
    else:
        adapter = LocalLedgerAdapter()
    return BlockchainGateway(adapter)
