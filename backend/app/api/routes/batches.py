from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.security import require_roles, get_current_user
from ...schemas import batch as batch_schemas
from ...schemas import lab as lab_schemas  # noqa: F401  (used via annotation below)

router = APIRouter(prefix="/api/v1/batches", tags=["batches"])

BATCH_MANAGERS = ("fpo", "processor", "admin", "institution")


@router.post("/merge", response_model=batch_schemas.MergeResult)
def merge_batches(
    payload: batch_schemas.MergeRequest,
    request: Request,
    user=Depends(require_roles(*BATCH_MANAGERS)),
) -> dict:
    result = request.app.state.services["batches"].merge(
        payload.batch_ids, payload.new_batch_code, user=user
    )
    if "error" in result:
        raise HTTPException(status_code=409, detail=result["error"])
    return result


@router.get("", response_model=list[batch_schemas.BatchRead])
def list_batches(request: Request, user=Depends(get_current_user)) -> list:
    return request.app.state.services["batches"].list_for_user(user=user)


@router.post("", response_model=batch_schemas.BatchRead, status_code=201)
def create_batch(
    payload: batch_schemas.BatchCreate,
    request: Request,
    user=Depends(require_roles(*BATCH_MANAGERS)),
) -> dict:
    result = request.app.state.services["batches"].create(
        data=payload.model_dump(), user=user
    )
    if "error" in result:
        # e.g. mass-balance violation (batch qty > linked harvest qty) or a
        # missing linked harvest. Surface it as a conflict, not a 500.
        raise HTTPException(status_code=409, detail=result["error"])
    return result


@router.get("/{batch_id}", response_model=batch_schemas.BatchRead)
def get_batch(
    batch_id: str, request: Request, user=Depends(get_current_user)
) -> dict:
    batch = request.app.state.services["batches"].get_for_user(batch_id, user=user)
    if batch is None:
        raise HTTPException(status_code=404, detail="Batch not found")
    return batch


@router.put("/{batch_id}", response_model=batch_schemas.BatchRead)
def update_batch(
    batch_id: str,
    payload: batch_schemas.BatchUpdate,
    request: Request,
    user=Depends(get_current_user),
) -> dict:
    batch = request.app.state.services["batches"].get_for_user(batch_id, user=user)
    if batch is None:
        raise HTTPException(status_code=404, detail="Batch not found")
    if user.role not in BATCH_MANAGERS and "status" in payload.model_dump(exclude_unset=True):
        raise HTTPException(status_code=403, detail="Only batch managers may change status")
    updated = request.app.state.repository.update_batch(
        batch_id, payload.model_dump(exclude_unset=True)
    )
    return updated


@router.get("/{batch_id}/genealogy", response_model=list[dict])
def genealogy(
    batch_id: str, request: Request, user=Depends(get_current_user)
) -> list:
    batch = request.app.state.services["batches"].get_for_user(batch_id, user=user)
    if batch is None:
        raise HTTPException(status_code=404, detail="Batch not found")
    return request.app.state.services["batches"].genealogy(batch_id)


@router.post("/{batch_id}/split", response_model=batch_schemas.SplitResult)
def split_batch(
    batch_id: str,
    payload: batch_schemas.SplitRequest,
    request: Request,
    user=Depends(require_roles(*BATCH_MANAGERS)),
) -> dict:
    result = request.app.state.services["batches"].split(
        batch_id, payload.child_quantities_kg, payload.origin_hint, user=user
    )
    if "error" in result:
        raise HTTPException(status_code=409, detail=result["error"])
    return result


@router.post("/{batch_id}/lab-test", response_model=dict, status_code=201)
def request_lab_test(
    batch_id: str,
    payload: lab_schemas.LabTestCreate,
    request: Request,
    user=Depends(require_roles(*BATCH_MANAGERS)),
) -> dict:
    batch = request.app.state.services["batches"].get_for_user(batch_id, user=user)
    if batch is None:
        raise HTTPException(status_code=404, detail="Batch not found")
    return request.app.state.services["labs"].request_test(
        batch_id=batch_id, lab_id=payload.lab_id, note=payload.requested_note
    )