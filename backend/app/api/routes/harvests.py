from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.security import require_roles, get_current_user
from ...schemas import harvest as harvest_schemas

router = APIRouter(prefix="/api/v1", tags=["harvests"])

CREATE_ROLES = ("beekeeper", "fpo", "admin")


@router.get("/harvests", response_model=list[harvest_schemas.HarvestRead])
def list_harvests(
    request: Request, user=Depends(get_current_user)
) -> list:
    return request.app.state.services["harvests"].list_for_user(user=user)


@router.post("/harvests", response_model=harvest_schemas.HarvestRead, status_code=201)
def create_harvest(
    payload: harvest_schemas.HarvestCreate,
    request: Request,
    user=Depends(require_roles(*CREATE_ROLES)),
) -> dict:
    return request.app.state.services["harvests"].create(
        beekeeper_id=user.user_id, data=payload.model_dump()
    )


@router.get("/harvests/{harvest_id}", response_model=harvest_schemas.HarvestRead)
def get_harvest(
    harvest_id: str, request: Request, user=Depends(get_current_user)
) -> dict:
    harvest = request.app.state.services["harvests"].get_for_user(harvest_id, user=user)
    if harvest is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Harvest not found")
    return harvest