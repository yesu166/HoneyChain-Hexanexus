from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.security import require_roles, get_current_user
from ...schemas import hive as hive_schemas

router = APIRouter(prefix="/api/v1", tags=["hives"])

CREATE_ROLES = ("beekeeper", "fpo", "admin")


@router.get("/hives", response_model=list[hive_schemas.HiveRead])
def list_hives(
    request: Request, user=Depends(get_current_user)
) -> list:
    return request.app.state.services["hives"].list_for_user(user=user)


@router.post("/hives", response_model=hive_schemas.HiveRead, status_code=201)
def create_hive(
    payload: hive_schemas.HiveCreate,
    request: Request,
    user=Depends(require_roles(*CREATE_ROLES)),
):
    return request.app.state.services["hives"].create(
        beekeeper_id=user.user_id, data=payload.model_dump()
    )


@router.get("/hives/{hive_id}", response_model=hive_schemas.HiveRead)
def get_hive(
    hive_id: str, request: Request, user=Depends(get_current_user)
) -> dict:
    hive = request.app.state.services["hives"].get_for_user(hive_id, user=user)
    if hive is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Hive not found")
    return hive


@router.put("/hives/{hive_id}", response_model=hive_schemas.HiveRead)
def update_hive(
    hive_id: str,
    payload: hive_schemas.HiveUpdate,
    request: Request,
    user=Depends(get_current_user),
) -> dict:
    hive = request.app.state.services["hives"].get_for_user(hive_id, user=user)
    if hive is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Hive not found")
    return request.app.state.services["hives"].update(
        hive_id, payload.model_dump(exclude_unset=True)
    )


@router.get("/hives/{hive_id}/readings", response_model=list[hive_schemas.ReadingRead])
def list_readings(
    hive_id: str, request: Request, user=Depends(get_current_user)
) -> list:
    hive = request.app.state.services["hives"].get_for_user(hive_id, user=user)
    if hive is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Hive not found")
    return request.app.state.services["hives"].readings(hive_id)


@router.post(
    "/hives/{hive_id}/readings", response_model=hive_schemas.ReadingRead, status_code=201
)
def add_reading(
    hive_id: str,
    payload: hive_schemas.ReadingCreate,
    request: Request,
    user=Depends(require_roles(*CREATE_ROLES)),
) -> dict:
    hive = request.app.state.services["hives"].get_for_user(hive_id, user=user)
    if hive is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Hive not found")
    return request.app.state.services["hives"].add_reading(
        hive_id, {**payload.model_dump(), "client_id": payload.client_id}
    )


@router.get("/hives/{hive_id}/health-score", response_model=hive_schemas.HealthScoreOut)
def health_score(
    hive_id: str, request: Request, user=Depends(get_current_user)
) -> dict:
    from datetime import datetime, timezone

    hive = request.app.state.services["hives"].get_for_user(hive_id, user=user)
    if hive is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Hive not found")
    assessment = request.app.state.risk_engine.assess(
        hive_id, request.app.state.services["hives"].readings(hive_id)
    )
    return {**vars(assessment), "timestamp": datetime.now(timezone.utc)}