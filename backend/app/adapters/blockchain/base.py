from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any


@dataclass
class AnchorReceipt:
    data_hash: str
    tx_hash: str
    chain_status: str  # anchored | pending | failed
    metadata: dict[str, Any]


class BlockchainAdapter(ABC):
    """Boundary for the proof-of-tamper provenance layer."""

    @abstractmethod
    async def anchor(self, payload: dict[str, Any]) -> AnchorReceipt: ...

    @abstractmethod
    async def verify(self, reference: str) -> bool: ...


def build_blockchain_adapter(name: str) -> BlockchainAdapter:
    from .fabric_adapter import FabricAdapter
    from .simulated_adapter import SimulatedBlockchainAdapter

    if name and name.lower() in ("fabric", "hyperledger"):
        return FabricAdapter()
    return SimulatedBlockchainAdapter()