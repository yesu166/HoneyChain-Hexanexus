"""Legacy compatibility shim for the blockchain adapter boundary.

The application now uses `BlockchainGateway` (gateway.py) as its single
ledger boundary — see the honest adapter split:

  - LocalLedgerAdapter    -> development/testing ONLY (never real chain)
  - EVMBlockchainAdapter   -> EVM when RPC/wallet/contract configured
  - FabricBlockchainAdapter -> Hyperledger Fabric when a network exists

This module keeps older callers working by re-exporting the gateway builder
and the anchor receipt record. It contains no simulated ledger anymore.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .gateway import (
    BlockchainGateway,
    EVMBlockchainAdapter,
    FabricBlockchainAdapter,
    LocalLedgerAdapter,
    build_blockchain_gateway,
)


@dataclass
class AnchorReceipt:
    """Legacy record kept for downstream type hints.

    New code should use BlockchainTransaction.snapshot() from gateway.state.
    """
    data_hash: str
    tx_hash: str
    chain_status: str  # anchored | pending | failed
    metadata: dict[str, Any]


def build_blockchain_adapter(name: str) -> BlockchainGateway:
    """Backward-compatible alias of build_blockchain_gateway().

    `name` is a historical hint ('simulated' -> local dev ledger, 'fabric' ->
    Fabric boundary, 'evm' -> EVM boundary). The gateway maps each name to the
    matching adapter and never fabricates a transaction when the ledger is
    unreachable.
    """
    from ...core.config import Settings, get_settings

    settings: Settings = get_settings()
    if name:  # honour an explicit override like tests used to set
        settings.blockchain_adapter = name
    return build_blockchain_gateway(settings)


__all__ = [
    "AnchorReceipt",
    "BlockchainGateway",
    "EVMBlockchainAdapter",
    "FabricBlockchainAdapter",
    "LocalLedgerAdapter",
    "build_blockchain_adapter",
    "build_blockchain_gateway",
]