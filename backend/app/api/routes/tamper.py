from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.config import get_settings
from ...core.rbac import require_permission
from ...core.security import get_current_user

router = APIRouter(prefix="/api/v1/admin", tags=["admin-demo"])


def _require_demo_mode(request: Request) -> None:
    """Tampering endpoints only exist in non-production environments."""
    settings = request.app.state.settings if hasattr(request.app.state, "settings") else get_settings()
    if settings.is_production:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tamper endpoints are disabled in production (DEMO_MODE only).",
        )


@router.post("/tamper/ledger/{chain_id}/{index}")
def tamper_ledger(
    chain_id: str,
    index: int,
    request: Request,
    user=Depends(require_permission("demo.tamper")),
) -> dict:
    """DEMO-ONLY: corrupt a ledger event so the hash chain flags it.

    Replays the tamper-evidence workflow. Never available in production.
    """
    _require_demo_mode(request)
    ledger = request.app.state.services["ledger"]
    try:
        ledger.tamper_chain(chain_id, index)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return ledger.verify_chain(chain_id)


@router.post("/tamper/evidence/{bundle_id}")
def tamper_evidence(
    bundle_id: str,
    request: Request,
    user=Depends(require_permission("demo.tamper")),
) -> dict:
    """DEMO-ONLY: flag an evidence bundle as tampered (see verify endpoint)."""
    _require_demo_mode(request)
    return {
        "bundle_id": bundle_id,
        "note": "Call POST /api/v1/evidence/bundles/{id}/verify to see tamper detection.",
        "demo_only": not get_settings().is_production,
    }