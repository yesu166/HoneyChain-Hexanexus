"""Evidence-linked assertion, reconciliation and impact routes.

Every route delegates to the service layer and returns what was actually
persisted. Nothing is synthesised at the API boundary.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.rbac import require_permission
from ...schemas import assertion as schemas
from ...services.assertion_service import AssertionRejected

router = APIRouter(prefix="/api/v1", tags=["assertions"])


def _services(request: Request) -> dict:
    return request.app.state.services


def _assertion_service(request: Request):
    return _services(request)["assertions"]


def _reconciliation_service(request: Request):
    return _services(request)["reconciliation"]


def _impact_service(request: Request):
    return _services(request)["impact"]


def _in_scope(request: Request, entity_type: str, entity_ref: str, user) -> None:
    """Assertions may only reference entities the caller can actually see."""
    if entity_type == "batch":
        if _services(request)["batches"].get_for_user(entity_ref, user=user) is None:
            raise HTTPException(status_code=403, detail="batch not in your scope")
    else:
        harvest = _services(request)["harvests"].get_for_user(entity_ref, user=user)
        if harvest is None:
            raise HTTPException(status_code=403, detail="harvest not in your scope")


@router.post(
    "/assertions",
    response_model=schemas.AssertionRead,
    status_code=status.HTTP_201_CREATED,
)
def create_assertion(
    payload: schemas.AssertionCreate,
    request: Request,
    user=Depends(require_permission("assertion.create")),
) -> dict:
    _in_scope(request, payload.entity_type, payload.entity_ref, user)
    try:
        return _assertion_service(request).create(
            user=user,
            entity_type=payload.entity_type,
            entity_ref=payload.entity_ref,
            action=payload.action,
            subject=payload.subject,
            asserted_quantity_kg=payload.asserted_quantity_kg,
            unit=payload.unit,
            organization_ref=payload.organization_ref,
            note=payload.note,
            nature=payload.nature,
            captured_at=payload.captured_at,
            device_id=payload.device_id,
            evidence_bundle_id=payload.evidence_bundle_id,
            evidence_root=payload.evidence_root,
            declared_authority=payload.declared_authority or "",
            client_id=payload.client_id,
            anchor=payload.anchor,
        )
    except AssertionRejected as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.get("/assertions/{entity_ref}", response_model=list[schemas.AssertionRead])
def list_assertions(
    entity_ref: str,
    request: Request,
    entity_type: str = "batch",
    user=Depends(require_permission("assertion.read")),
) -> list:
    _in_scope(request, entity_type, entity_ref, user)
    return _assertion_service(request).list_for(entity_ref)


@router.get(
    "/assertions/{entity_ref}/verification",
    response_model=schemas.VerificationStateRead,
)
def verification_state(
    entity_ref: str,
    request: Request,
    entity_type: str = "batch",
    user=Depends(require_permission("assertion.read")),
) -> dict:
    _in_scope(request, entity_type, entity_ref, user)
    return _assertion_service(request).verification_state(
        entity_ref, entity_type=entity_type
    )

@router.post("/assertions/{entity_ref}/reconcile")
def reconcile(
    entity_ref: str,
    payload: schemas.ReconcileRequest,
    request: Request,
    user=Depends(require_permission("assertion.reconcile")),
) -> dict:
    """Compare every organization's current claim and open discrepancies."""
    if _services(request)["batches"].get_for_user(entity_ref, user=user) is None:
        raise HTTPException(status_code=403, detail="batch not in your scope")
    return _reconciliation_service(request).detect(
        entity_ref=entity_ref,
        subject=payload.subject,
        tolerance_kg=payload.tolerance_kg,
        tolerance_pct=payload.tolerance_pct,
        actor_ref=str(getattr(user, "user_id", "") or ""),
    )


@router.get("/assertions/{entity_ref}/discrepancies")
def list_discrepancies(
    entity_ref: str,
    request: Request,
    user=Depends(require_permission("assertion.read")),
) -> dict:
    if _services(request)["batches"].get_for_user(entity_ref, user=user) is None:
        raise HTTPException(status_code=403, detail="batch not in your scope")
    rows = _reconciliation_service(request).ledger(entity_ref)
    open_rows = [r for r in rows if r.get("status") in ("OPEN", "UNDER_REVIEW")]
    return {
        "entity_ref": entity_ref,
        "discrepancies": rows,
        "open_count": len(open_rows),
    }


@router.post("/assertions/{entity_ref}/discrepancies/{discrepancy_id}/resolve")
def resolve_discrepancy(
    entity_ref: str,
    discrepancy_id: str,
    payload: schemas.ResolveRequest,
    request: Request,
    user=Depends(require_permission("assertion.reconcile")),
) -> dict:
    if _services(request)["batches"].get_for_user(entity_ref, user=user) is None:
        raise HTTPException(status_code=403, detail="batch not in your scope")
    try:
        return _reconciliation_service(request).resolve(
            entity_ref=entity_ref,
            discrepancy_id=discrepancy_id,
            state=payload.state,
            note=payload.note,
            evidence_bundle_id=payload.evidence_bundle_id,
            evidence_root=payload.evidence_root,
            actor_ref=str(getattr(user, "user_id", "") or ""),
        )
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post(
    "/assertions/{entity_ref}/impact",
    response_model=schemas.ImpactRead,
)
def analyse_impact(
    entity_ref: str,
    payload: schemas.ImpactRequest,
    request: Request,
    user=Depends(require_permission("provenance.impact.read")),
) -> dict:
    """Identify the affected downstream lineage of [entity_ref] (append-only)."""
    if _services(request)["batches"].get_for_user(entity_ref, user=user) is None:
        raise HTTPException(status_code=403, detail="batch not in your scope")
    try:
        return _impact_service(request).analyse(
            entity_ref=entity_ref,
            reason=payload.reason,
            evidence_bundle_id=payload.evidence_bundle_id,
            evidence_root=payload.evidence_root,
            status=payload.status,
            actor_ref=str(getattr(user, "user_id", "") or ""),
        )
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.get("/assertions/{entity_ref}/impacts")
def list_impacts(
    entity_ref: str,
    request: Request,
    user=Depends(require_permission("provenance.impact.read")),
) -> dict:
    if _services(request)["batches"].get_for_user(entity_ref, user=user) is None:
        raise HTTPException(status_code=403, detail="batch not in your scope")
    rows = _impact_service(request).impacts_for(entity_ref)
    return {"entity_ref": entity_ref, "impacts": rows, "count": len(rows)}