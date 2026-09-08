from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.security import require_roles, get_current_user
from ...schemas import lab as lab_schemas

router = APIRouter(prefix="/api/v1", tags=["labs"])


@router.get("/labs/{lab_id}/queue", response_model=list[lab_schemas.LabQueueItem])
def lab_queue(
    lab_id: str, request: Request, user=Depends(get_current_user)
) -> list:
    if user.role not in ("lab", "admin", "institution"):
        raise HTTPException(status_code=403, detail="Lab role required")
    return request.app.state.services["labs"].queue(lab_id, user=user)


@router.get("/batches/{batch_id}/lab-tests", response_model=list[lab_schemas.LabTestRead])
def lab_tests_for_batch(
    batch_id: str, request: Request, user=Depends(get_current_user)
) -> list:
    request.app.state.services["batches"].get_for_user(batch_id, user=user)
    return request.app.state.services["labs"].for_batch(batch_id)


@router.post(
    "/labs/tests/{test_id}/result",
    response_model=lab_schemas.LabTestRead,
)
def submit_result(
    test_id: str,
    payload: lab_schemas.LabResultSubmit,
    request: Request,
    user=Depends(require_roles("lab")),
) -> dict:
    updated = request.app.state.services["labs"].submit_result(
        test_id,
        result=payload.result,
        tested_by=payload.tested_by or user.user_id,
        notes=payload.notes,
    )
    if updated is None:
        raise HTTPException(status_code=404, detail="Lab test not found")
    return updated