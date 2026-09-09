"""Blockchain transaction state machine.

Tracks the lifecycle of a ledger submission independently of the database so
that DB state and ledger state stay consistent:

PENDING → SUBMITTED → CONFIRMED
            |            |
            v            v
        RETRYING      FAILED / UNKNOWN

Truth rule: PENDING never becomes CONFIRMED without an actual confirmation
signal from the ledger adapter. A submission that fails/expires lands in
FAILED/UNKNOWN and may be retried (idempotently).
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any


class TxState:
    """Canonical transaction states (see prompt §31/§141.10)."""

    NOT_CONFIGURED = "NOT_CONFIGURED"
    PENDING = "PENDING"
    SUBMITTED = "SUBMITTED"
    CONFIRMED = "CONFIRMED"
    FAILED = "FAILED"
    RETRYING = "RETRYING"
    UNKNOWN = "UNKNOWN"

    _TERMINAL = {CONFIRMED, FAILED}
    _ORDER = {PENDING: 0, RETRYING: 1, SUBMITTED: 2, UNKNOWN: 3, FAILED: 4, CONFIRMED: 5}


@dataclass
class BlockchainTransaction:
    tx_ref: str  # idempotency / anchor id
    operation: str  # submit_anchor, submit_custody_transfer, ...
    state: str = TxState.PENDING
    attempts: int = 0
    max_attempts: int = 3
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    tx_hash: str = ""
    block_number: str = ""
    network: str = ""
    error: str = ""
    payload_hash: str = ""
    metadata: dict[str, Any] = field(default_factory=dict)

    def mark_submitted(self, tx_hash: str, network: str = "") -> None:
        self._bump()
        self.state = TxState.SUBMITTED
        self.tx_hash = tx_hash
        self.network = network or self.network

    def mark_confirmed(self, block_number: str = "") -> None:
        self._bump()
        self.state = TxState.CONFIRMED
        self.block_number = block_number or self.block_number

    def mark_failed(self, error: str) -> None:
        self._bump()
        self.state = TxState.FAILED
        self.error = error

    def mark_unknown(self, error: str = "") -> None:
        self._bump()
        self.state = TxState.UNKNOWN
        self.error = error or self.error

    def retry(self) -> bool:
        """Move SUBMITTED/FAILED/UNKNOWN back to RETRYING if under the cap.

        Returns False when no more attempts are allowed (terminal FAILED).
        """
        if self.state in (TxState.CONFIRMED,):
            return False
        if self.attempts >= self.max_attempts:
            self.state = TxState.FAILED
            return False
        self._bump()
        self.attempts += 1
        self.state = TxState.RETRYING
        return True

    def _bump(self) -> None:
        self.updated_at = time.time()

    def snapshot(self) -> dict[str, Any]:
        return {
            "tx_ref": self.tx_ref,
            "operation": self.operation,
            "state": self.state,
            "attempts": self.attempts,
            "max_attempts": self.max_attempts,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "tx_hash": self.tx_hash,
            "block_number": self.block_number,
            "network": self.network,
            "payload_hash": self.payload_hash,
            "error": self.error,
        }


class TransactionTracker:
    """In-memory idempotent tracker keyed by tx_ref (anchor id)."""

    def __init__(self) -> None:
        self._txs: dict[str, BlockchainTransaction] = {}

    def begin(
        self,
        tx_ref: str,
        operation: str,
        *,
        max_attempts: int = 3,
    ) -> BlockchainTransaction:
        existing = self._txs.get(tx_ref)
        if existing is not None:
            return existing
        tx = BlockchainTransaction(
            tx_ref=tx_ref, operation=operation, max_attempts=max_attempts
        )
        self._txs[tx_ref] = tx
        return tx

    def get(self, tx_ref: str) -> BlockchainTransaction | None:
        return self._txs.get(tx_ref)

    def list(self) -> list[BlockchainTransaction]:
        return list(self._txs.values())

    def reset(self) -> None:
        self._txs.clear()
