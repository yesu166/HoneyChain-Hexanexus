from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.rbac import require_permission
from ...core.security import get_current_user
from ...schemas import lineage as lineage_schemas

router = APIRouter(prefix="/api/v1", tags=["lineage"])


@router.post(
    "/batches/transition",
    response_model=lineage_schemas.LineageStateRead,
)
def batch_transition(
    payload: lineage_schemas.StateTransition,
    request: Request,
    user=Depends(require_permission("batch.update_status")),
) -> dict:
    from ...services.lineage_service import StateTransitionError

    try:
        return request.app.state.services["lineage"].transition(
            batch_id=payload.batch_id,
            to_state=payload.to_state,
            actor_ref=payload.actor_ref or user.user_id,
            note=payload.note,
        )
    except StateTransitionError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/batches/{batch_id}/state")
def batch_state(batch_id: str, request: Request, user=Depends(get_current_user)) -> dict:
    services = request.app.state.services
    batch = services["batches"].get_for_user(batch_id, user=user)
    if batch is None:
        raise HTTPException(status_code=404, detail="batch not found")
    holder = services["lineage"].current_holder(batch_id)
    return {
        "batch_id": batch_id,
        "status": batch.get("status", "created"),
        "trust_tier": batch.get("trust_tier", "self_declared"),
        "holder": holder,
    }


@router.get("/batches/{batch_id}/lineage")
def batch_lineage(batch_id: str, request: Request) -> dict:
    services = request.app.state.services
    tree = services["batches"].genealogy(batch_id)
    chain = services["ledger"].verify_chain(batch_id)
    return {
        "batch_id": batch_id,
        "genealogy": tree,
        "ledger": chain,
    }