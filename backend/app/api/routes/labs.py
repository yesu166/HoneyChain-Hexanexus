from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.security import require_roles, get_current_user
from ...schemas import lab as lab_schemas

router = APIRouter(prefix="/api/v1", tags=["labs"])


@router.get("/labs", response_model=list[lab_schemas.LabOrganization])
def list_labs(request: Request, user=Depends(get_current_user)) -> list:
    """Laboratory directory for the FPO test-request selector.

    Returns real organization rows only. Any authenticated user who may request
    a test needs this to pick a real lab instead of typing an arbitrary id.
    """
    if user.role not in ("fpo", "lab", "admin", "institution", "processor"):
        raise HTTPException(status_code=403, detail="Not permitted to list labs")
    return request.app.state.services["labs"].list_labs()


@router.post("/labs/tests/{test_id}/start", response_model=lab_schemas.LabTestRead)
def start_test(
    test_id: str,
    request: Request,
    user=Depends(require_roles("lab")),
) -> dict:
    """Move a requested test into explicit IN TESTING state."""
    services = request.app.state.services
    test = request.app.state.repository.get_lab_test(test_id)
    if test is None:
        raise HTTPException(status_code=404, detail="Lab test not found")
    owner = test.get("lab_id") or ""
    if user.org_id and owner and owner != user.org_id:
        raise HTTPException(status_code=403, detail="lab test is not in your scope")
    updated = services["labs"].start_test(test_id, actor_ref=user.user_id)
    if updated is None:
        raise HTTPException(status_code=404, detail="Lab test not found")
    return updated


@router.get("/labs/{lab_id}/queue", response_model=list[lab_schemas.LabQueueItem])
def lab_queue(
    lab_id: str, request: Request, user=Depends(get_current_user)
) -> list:
    if user.role not in ("lab", "admin", "institution"):
        raise HTTPException(status_code=403, detail="Lab role required")
    # A lab may only service its own org's queue/pending tests.
    if user.role == "lab" and user.org_id and lab_id != user.org_id:
        raise HTTPException(status_code=403, detail="lab not in your scope")
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
    services = request.app.state.services
    test = request.app.state.repository.get_lab_test(test_id)
    if test is None:
        raise HTTPException(status_code=404, detail="Lab test not found")
    # Only the lab that owns the test may record its result.
    owner = test.get("lab_id") or ""
    if user.org_id and owner and owner != user.org_id:
        raise HTTPException(status_code=403, detail="lab test is not in your scope")
    updated = services["labs"].submit_result(
        test_id,
        result=payload.result,
        tested_by=payload.tested_by or user.user_id,
        notes=payload.notes,
    )
    if updated is None:
        raise HTTPException(status_code=404, detail="Lab test not found")
    return updated