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
    def verify_anchor(self, ref: str, expected_root: str = "") -> bool:
        """True only when [ref] can be proven anchored on the ledger.

        When [expected_root] is given, prove that [expected_root] is the
        current commitment for [ref] on the ledger (batch-scoped verify),
        instead of merely that [ref] has an anchor on the ledger."""

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

    def verify_anchor(self, ref, expected_root=""):
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

    def verify_anchor(self, ref, expected_root=""):
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

    def _evaluate(self, fn: str, args: list[str]) -> dict[str, Any]:
        """Evaluate (query) a read function and parse the chaincode result."""
        resp = self._http_request(
            "POST", "/evaluate", {"function": fn, "args": args}, timeout=30
        )
        self._classify_gateway_response(resp)
        result = resp.get("result", {})
        if isinstance(result, str):
            try:
                result = _json.loads(result)
            except Exception:
                pass
        return result if isinstance(result, dict) else {"result": result}

    def _ensure_batch_on_ledger(
        self, batch_id: str, *, organization_ref: str = ""
    ) -> None:
        """Ensure BATCH:{batch_id} exists on the Fabric ledger before anchoring.

        A real getBatch probe decides: only when the chaincode reports NOT_FOUND
        does the adapter issue createBatch — it never guesses or fabricates
        ledger state. Skipped for ids that cannot be app batch ids (the app's
        batch ids are uuid-shaped, e.g. from Supabase row ids)."""
        if not (batch_id and len(batch_id) == 36 and batch_id.count("-") == 4):
            return
        try:
            self._evaluate(CHAINCODE_FUNCTIONS["GET_BATCH"], [batch_id])
            return
        except LedgerUnavailable as exc:
            if "NOT_FOUND" not in str(exc):
                raise
        from datetime import datetime, timezone

        actor = organization_ref or "honeychain-backend"
        org = organization_ref or "honeychain"
        batch_json = _json.dumps({
            "batchId": batch_id,
            "batchType": "honey_batch",
            "sourceHiveIds": [],
            "parentBatchIds": [],
            "actorId": actor,
            "organizationId": org,
            "serverTimestamp": datetime.now(timezone.utc).isoformat(),
            "metadata": {},
        })
        body = {
            "function": CHAINCODE_FUNCTIONS["CREATE_BATCH"],
            "args": [batch_json],
        }
        resp = self._http_request("POST", "/submit", body, timeout=60)
        self._classify_gateway_response(resp)

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
        if batch_id:
            self._ensure_batch_on_ledger(
                batch_id, organization_ref=payload.get("organization_ref", "")
            )
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
        if isinstance(result, str):
            try:
                result = _json.loads(result)
            except Exception:
                result = {"raw": result}

        # The REAL transaction id comes from the gateway (Fabric Gateway SDK
        # proposal txid). The chaincode's own blockchainTxId field is used as
        # a fallback for older gateway builds that still return it. The adapter
        # never fabricates an id when neither is present — an empty tx_hash is
        # stored honestly and the passport will show chain_status=pending.
        gateway_tx_id = str(resp.get("tx_id") or "")
        blockchain_tx_id = result.get("blockchainTxId", "") if isinstance(result, dict) else ""
        tx_hash = gateway_tx_id or str(blockchain_tx_id or "")

        return {
            "tx_hash": tx_hash,
            "network": f"fabric:{self._channel}",
            "state": TxState.CONFIRMED,
            "fabric_result": result,
        }

    def verify_anchor(self, ref, expected_root=""):
        if not self.configured:
            raise LedgerNotConfigured("FABRIC_NOT_CONFIGURED")

        if expected_root:
            # verifyMerkleRoot(batchId, expectedRoot) — a live on-ledger proof
            # that this exact root is the batch's current commitment.
            resp = self._http_request(
                "POST",
                "/evaluate",
                {
                    "function": CHAINCODE_FUNCTIONS["VERIFY_MERKLE_ROOT"],
                    "args": [ref, expected_root],
                },
                timeout=30,
            )
            self._classify_gateway_response(resp)
            result = resp.get("result", {})
            if isinstance(result, str):
                try:
                    result = _json.loads(result)
                except Exception:
                    return False
            return result.get("verified", False) is True

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

    # Domain event type -> chaincode EVENT_TYPES whitelist (lib/events.js).
    _CHAINCODE_EVENT_TYPES = {
        "batch_state_transition": "BATCH_TRANSFORMED",
        "custody_transfer": "CUSTODY_TRANSFERRED",
        "certificate_anchor": "LAB_CERTIFICATE_ANCHORED",
        "harvest_declared": "HARVEST_DECLARED",
        "harvest_field_verified": "HARVEST_FIELD_VERIFIED",
        "harvest_evidence_anchored": "HARVEST_EVIDENCE_ANCHORED",
        "lab_sample_registered": "LAB_SAMPLE_REGISTERED",
        "batch_created": "BATCH_CREATED",
        "batch_split": "BATCH_SPLIT",
        "batch_merged": "BATCH_MERGED",
        "packaging_recorded": "PACKAGING_RECORDED",
        "dispatch_recorded": "DISPATCH_RECORDED",
        "retail_received": "RETAIL_RECEIVED",
        "passport_issued": "PASSPORT_ISSUED",
        "passport_revoked": "PASSPORT_REVOKED",
        "provenance_anchored": "PROVENANCE_ANCHORED",
        "provenance_verified": "PROVENANCE_VERIFIED",
        "evidence_mismatch_detected": "EVIDENCE_MISMATCH_DETECTED",
        "dispute_opened": "DISPUTE_OPENED",
        "dispute_resolved": "DISPUTE_RESOLVED",
    }

    def submit_event(self, event, tx_ref):
        if not self.configured:
            raise LedgerNotConfigured("FABRIC_NOT_CONFIGURED")

        domain_type = event.get("type", event.get("eventType", ""))
        if domain_type == "lineage_event":
            operation = str(event.get("operation", "")).upper()
            event_type = (
                "BATCH_SPLIT" if operation == "SPLIT"
                else "BATCH_MERGED" if operation in ("MERGE", "AGGREGATE")
                else "PROVENANCE_ANCHORED"
            )
        else:
            event_type = self._CHAINCODE_EVENT_TYPES.get(domain_type, "")
        if not event_type:
            raise LedgerUnavailable(
                "FABRIC_TRANSACTION_FAILED: "
                f"no chaincode event type for domain event '{domain_type}'"
            )

        from datetime import datetime, timezone

        from ...core.crypto import hash_payload as _hp

        event_payload = {
            "eventId": event.get("event_id", tx_ref[:40]),
            "eventType": event_type,
            "entityType": event.get("entity_type", "batch"),
            "entityId": event.get("entity_id", event.get("batch_id", "")),
            "actorId": event.get("actor_id", "honeychain-backend"),
            "organizationId": event.get("organization_ref", "honeychain"),
            "serverTimestamp": datetime.now(timezone.utc).isoformat(),
            "payloadHash": _hp(event),
            "metadata": event,
        }
        if not event_payload["entityId"]:
            raise LedgerUnavailable(
                f"FABRIC_TRANSACTION_FAILED: event '{domain_type}' has no entity id"
            )
        event_json = _json.dumps(event_payload)

        body = {
            "function": CHAINCODE_FUNCTIONS["SUBMIT_EVENT"],
            "args": [event_json],
        }

        resp = self._http_request("POST", "/submit", body, timeout=60)
        self._classify_gateway_response(resp)

        result = resp.get("result", {})
        if isinstance(result, str):
            try:
                result = _json.loads(result)
            except Exception:
                result = {"raw": result}

        gateway_tx_id = str(resp.get("tx_id") or "")
        blockchain_tx_id = result.get("blockchainTxId", "") if isinstance(result, dict) else ""
        tx_hash = gateway_tx_id or str(blockchain_tx_id or "")

        return {
            "tx_hash": tx_hash,
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

    def verify_anchor(self, ref: str, expected_root: str = "") -> bool:
        try:
            return self._adapter.verify_anchor(ref, expected_root)
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
    """Build the gateway from config.

    Ledger integration is selected by configuration:
      - EVM:   BLOCKCHAIN_RPC_URL, BLOCKCHAIN_CHAIN_ID, BLOCKCHAIN_CONTRACT,
               BLOCKCHAIN_PRIVATE_KEY (never committed)
      - FABRIC via bridge (production): BLOCKCHAIN_ADAPTER=remote_fabric,
               FABRIC_BRIDGE_URL, FABRIC_BRIDGE_TOKEN, FABRIC_CHANNEL,
               FABRIC_CHAINCODE

    PRODUCTION FAILS CLOSED. A local in-process ledger is a development and test
    device; letting it become the production ledger would let a public host
    report provenance anchors that exist in no chain at all, and label them as
    if they did. So in production the local adapter is refused outright and the
    remote Fabric bridge is required, exactly as `build_repository` already
    requires Supabase. There is no silent fallback: a misconfigured production
    deployment fails to start rather than quietly serving fake provenance.
    """
    if settings is None:
        from ...core.config import get_settings

        settings = get_settings()

    adapter_name = getattr(settings, "blockchain_adapter", "local")
    normalized = adapter_name.lower()
    is_production = bool(getattr(settings, "is_production", False))

    if normalized in ("simulated", "local", "memory", ""):
        # 'simulated' is the legacy name for the local dev/testing ledger.
        if is_production:
            raise RuntimeError(
                "BLOCKCHAIN_ADAPTER is the local in-process ledger, which is a "
                "development/test device and must never be the production "
                "ledger. Set BLOCKCHAIN_ADAPTER=remote_fabric together with "
                "FABRIC_BRIDGE_URL, FABRIC_BRIDGE_TOKEN, FABRIC_CHANNEL and "
                "FABRIC_CHAINCODE. Refusing to start rather than reporting "
                "provenance that exists in no chain."
            )
        adapter = LocalLedgerAdapter()
    elif normalized in ("evm", "ethereum", "polygon"):
        adapter = EVMBlockchainAdapter(
            rpc_url=getattr(settings, "blockchain_rpc_url", ""),
            chain_id=getattr(settings, "blockchain_chain_id", ""),
            contract_address=getattr(settings, "blockchain_contract", ""),
            private_key_hex=getattr(settings, "blockchain_private_key", ""),
        )
    elif normalized in ("fabric", "hyperledger"):
        adapter = FabricBlockchainAdapter(
            channel=getattr(settings, "fabric_channel", ""),
            chaincode=getattr(settings, "fabric_chaincode", ""),
            gateway_url=getattr(settings, "fabric_gateway_url", ""),
        )
    elif normalized in ("remote_fabric", "fabric_bridge", "fabric_remote"):
        # Public API deployment that forwards to the internal Fabric service on
        # EC2. Same real chain, same honest FABRIC_* states, no local fallback.
        from .bridge import RemoteFabricAdapter

        bridge_url = getattr(settings, "fabric_bridge_url", "")
        bridge_token = getattr(settings, "fabric_bridge_token", "")
        channel = getattr(settings, "fabric_channel", "")
        chaincode = getattr(settings, "fabric_chaincode", "")
        # Missing bridge configuration is refused up front rather than
        # producing a gateway that accepts writes and reports them as anchored.
        missing = [
            name
            for name, value in (
                ("FABRIC_BRIDGE_URL", bridge_url),
                ("FABRIC_BRIDGE_TOKEN", bridge_token),
                ("FABRIC_CHANNEL", channel),
                ("FABRIC_CHAINCODE", chaincode),
            )
            if not str(value or "").strip()
        ]
        if missing and is_production:
            raise RuntimeError(
                "BLOCKCHAIN_ADAPTER=remote_fabric requires "
                + ", ".join(missing)
                + ". Refusing to start with an unconfigured Fabric bridge rather "
                "than falling back to the local ledger."
            )
        adapter = RemoteFabricAdapter(
            bridge_url=bridge_url,
            service_token=bridge_token,
            timeout=getattr(settings, "fabric_bridge_timeout", 30),
            channel=channel,
            chaincode=chaincode,
        )
    else:
        if is_production:
            raise RuntimeError(
                f"Unknown BLOCKCHAIN_ADAPTER={adapter_name!r}. Production must "
                "use remote_fabric; refusing to fall back to the local ledger."
            )
        adapter = LocalLedgerAdapter()
    return BlockchainGateway(adapter)
