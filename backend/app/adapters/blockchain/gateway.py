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
# Fabric boundary
# ---------------------------------------------------------------------------

class FabricBlockchainAdapter(LedgerAdapter):
    """Hyperledger Fabric adapter.

    A permissioned consortium chain is valuable when genuinely independent
    organizations write/validate records. This boundary is implemented from
    the LedgerAdapter contract, but it will NOT simulate Fabric transactions,
    blocks, peers, orderers, MSP identities, payloads or ledger state.

    Without a working Fabric network it reports:
      FABRIC_NOT_CONFIGURED / FABRIC_UNAVAILABLE / FABRIC_TRANSACTION_FAILED
    """

    ledger_name = "fabric"

    def __init__(self, *, channel: str = "", chaincode: str = "") -> None:
        self._channel = channel
        self._chaincode = chaincode

    @property
    def configured(self) -> bool:
        return bool(self._channel and self._chaincode)

    def submit_anchor(self, payload, tx_ref):
        if not self.configured:
            raise LedgerNotConfigured(
                "FABRIC_NOT_CONFIGURED: no Fabric channel/chaincode configured "
                "and no real network is reachable. No fake transaction created."
            )
        raise LedgerUnavailable(
            "FABRIC_UNAVAILABLE: Fabric Gateway connection profile / peer / "
            "orderer / MSP not reachable in this environment."
        )

    def verify_anchor(self, ref):
        if not self.configured:
            raise LedgerNotConfigured("FABRIC_NOT_CONFIGURED")
        raise LedgerUnavailable("FABRIC_QUERY_FAILED: no reachable Fabric peer.")

    def get_transaction_status(self, tx_hash):
        if not self.configured:
            raise LedgerNotConfigured("FABRIC_NOT_CONFIGURED")
        raise LedgerUnavailable("FABRIC_QUERY_FAILED: no reachable Fabric peer.")


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
        )
    else:
        adapter = LocalLedgerAdapter()
    return BlockchainGateway(adapter)
