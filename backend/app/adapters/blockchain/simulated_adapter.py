from __future__ import annotations

import hashlib
import json
import uuid
from datetime import datetime, timezone
from typing import Any

from .base import AnchorReceipt, BlockchainAdapter


class SimulatedBlockchainAdapter(BlockchainAdapter):
    """Local/demo ledger.

    Tamper-evidence only: it hashes the payload and tracks it in-process. It is
    explicitly NOT a real distributed ledger and never claims to be one. A real
    deployment swaps this for the Fabric adapter (or another ledger adapter).
    """

    def __init__(self) -> None:
        self._ledger: dict[str, dict[str, Any]] = {}

    async def anchor(self, payload: dict[str, Any]) -> AnchorReceipt:
        canonical = json.dumps(payload, sort_keys=True, default=str)
        data_hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
        tx_hash = f"SIM-{uuid.uuid4().hex[:32]}"
        self._ledger[data_hash] = {
            "tx_hash": tx_hash,
            "anchored_at": datetime.now(timezone.utc).isoformat(),
        }
        return AnchorReceipt(
            data_hash=data_hash,
            tx_hash=tx_hash,
            chain_status="anchored",
            metadata={"ledger": "simulated"},
        )

    async def verify(self, reference: str) -> bool:
        return reference in self._ledger