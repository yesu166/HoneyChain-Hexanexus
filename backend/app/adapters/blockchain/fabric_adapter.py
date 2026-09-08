from __future__ import annotations

from typing import Any

from .base import AnchorReceipt, BlockchainAdapter


class FabricAdapter(BlockchainAdapter):
    """Hyperledger Fabric adapter boundary.

    Intentionally a placeholder: it raises unless the Fabric Gateway SDK is
    configured. This keeps the mobile app free of any direct ledger dependency —
    anchoring goes Flutter -> FastAPI -> adapter -> ledger.
    """

    def __init__(self, channel: str = "honeychain", chaincode: str = "tracer") -> None:
        self._channel = channel
        self._chaincode = chaincode

    async def anchor(self, payload: dict[str, Any]) -> AnchorReceipt:
        raise NotImplementedError(
            "FabricAdapter is a placeholder. Configure the Fabric Gateway "
            "SDK/connection profile and implement 'anchor' before production use."
        )

    async def verify(self, reference: str) -> bool:
        raise NotImplementedError(
            "FabricAdapter is a placeholder. Configure the Fabric Gateway "
            "SDK/connection profile and implement 'verify' before production use."
        )