from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.security import require_roles, get_current_user
from ...schemas import custody as custody_schemas

router = APIRouter(prefix="/api/v1/batches", tags=["custody"])

CUSTODY_WRITERS = ("fpo", "processor", "admin", "institution", "beekeeper")


@router.post("/{batch_id}/custody-events", response_model=dict, status_code=201)
def add_custody_event(
    batch_id: str,
    payload: custody_schemas.CustodyEventCreate,
    request: Request,
    user=Depends(require_roles(*CUSTODY_WRITERS)),
) -> dict:
    batch = request.app.state.services["batches"].get_for_user(batch_id, user=user)
    if batch is None:
        raise HTTPException(status_code=404, detail="Batch not found")
    if payload.batch_id != batch_id:
        raise HTTPException(status_code=409, detail="Custody batch_id does not match route")
    try:
        return request.app.state.services["custody"].add(
            batch_id=batch_id,
            # The authenticated user is the only authoritative actor.
            data={**payload.model_dump(), "actor": user.user_id},
        )
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.get("/{batch_id}/custody-events", response_model=list[custody_schemas.CustodyEventRead])
def list_custody_events(
    batch_id: str, request: Request, user=Depends(get_current_user)
) -> list:
    batch = request.app.state.services["batches"].get_for_user(batch_id, user=user)
    if batch is None:
        raise HTTPException(status_code=404, detail="Batch not found")
    return request.app.state.services["custody"].list(batch_id)