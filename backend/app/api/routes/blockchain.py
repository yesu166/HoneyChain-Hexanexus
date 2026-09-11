from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.rbac import require_permission
from ...core.security import get_current_user

router = APIRouter(prefix="/api/v1/blockchain", tags=["blockchain"])


@router.get("/status")
def blockchain_status(request: Request, user=Depends(get_current_user)) -> dict[str, Any]:
    gateway = request.app.state.services["gateway"]
    adapter = gateway._adapter

    # For Fabric adapter: do a real health check against the live network
    if hasattr(adapter, "health_check"):
        health = adapter.health_check()
        return {
            "adapter": gateway.ledger_name,
            "ledger": gateway.ledger_name,
            "tracker": {
                "transactions": len(gateway.transaction_snapshots()),
            },
            "transactions": gateway.transaction_snapshots(),
            "fabric": health,
        }

    return {
        "adapter": gateway.ledger_name,
        "ledger": gateway.ledger_name,
        "tracker": {
            "transactions": len(gateway.transaction_snapshots()),
        },
        "transactions": gateway.transaction_snapshots(),
    }


@router.get("/health")
def blockchain_health(request: Request) -> dict[str, Any]:
    """Public blockchain health check (no auth required).

    Returns honest status of the configured blockchain adapter.
    Never claims connected when the real Fabric path has not executed.
    """
    gateway = request.app.state.services["gateway"]
    adapter = gateway._adapter

    if hasattr(adapter, "health_check"):
        return adapter.health_check()

    return {
        "adapter": gateway.ledger_name,
        "status": "local",
        "channel": "",
        "chaincode": "",
        "chaincode_version": None,
        "chaincode_sequence": None,
        "peer": "",
        "last_verified_at": None,
        "error": None,
    }


@router.get("/transactions/{tx_ref}")
def transaction_status(tx_ref: str, request: Request, user=Depends(get_current_user)) -> dict[str, Any]:
    tx = request.app.state.services["gateway"].get_transaction_status(tx_ref)
    if tx is None:
        raise HTTPException(status_code=404, detail="transaction not found")
    return tx


@router.post("/transactions/{tx_ref}/retry")
def retry_transaction(tx_ref: str, request: Request, user=Depends(get_current_user)) -> dict[str, Any]:
    gateway = request.app.state.services["gateway"]
    if not gateway.retry(tx_ref):
        raise HTTPException(status_code=400, detail="cannot retry (confirm or cap reached)")
    return {"tx_ref": tx_ref, "state": gateway.get_transaction_status(tx_ref)}