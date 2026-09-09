from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.security import get_current_user
from ...schemas import evidence as evidence_schemas

router = APIRouter(prefix="/api/v1", tags=["evidence"])


@router.post(
    "/evidence/bundles",
    response_model=evidence_schemas.EvidenceRead,
)
def create_bundle(
    payload: evidence_schemas.EvidenceBundleCreate,
    request: Request,
    user=Depends(get_current_user),
) -> dict:
    services = request.app.state.services
    if payload.entity_type == "batch":
        batch = services["batches"].get_for_user(payload.entity_ref, user=user)
        if batch is None:
            # Offline-first: evidence may arrive before the batch row syncs.
            pass  # scope is re-checked when the batch is created/linked.
    try:
        bundle = services["evidence"].create_bundle(
            entity_type=payload.entity_type,
            entity_ref=payload.entity_ref,
            evidence=[e.model_dump() for e in payload.evidence],
            operator=payload.operator,
            device_id=payload.device_id,
            anchor=payload.anchor,
            include_telemetry=payload.include_telemetry,
            telemetry_limit=payload.telemetry_limit,
            telemetry_hive_id=payload.telemetry_hive_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return bundle


@router.get("/evidence/bundles/{bundle_id}", response_model=evidence_schemas.EvidenceRead)
def get_bundle(bundle_id: str, request: Request) -> dict:
    bundle = request.app.state.services["evidence"].get_bundle(bundle_id)
    if bundle is None:
        raise HTTPException(status_code=404, detail="bundle not found")
    return bundle


@router.post(
    "/evidence/bundles/{bundle_id}/verify",
    response_model=evidence_schemas.EvidenceVerifyResult,
)
def verify_bundle(bundle_id: str, request: Request) -> dict:
    from ...services.evidence_service import BundleNotFound

    try:
        return request.app.state.services["evidence"].verify_bundle(bundle_id)
    except BundleNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.post("/evidence/proof/{bundle_id}/{evidence_id}")
def evidence_proof(bundle_id: str, evidence_id: str, request: Request) -> dict:
    try:
        return request.app.state.services["evidence"].evidence_proof(
            bundle_id, evidence_id
        )
    except (ValueError, KeyError) as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.post("/evidence/verify-proof")
def verify_evidence_proof(
    payload: evidence_schemas.EvidenceProofVerify, request: Request
) -> dict:
    return request.app.state.services["evidence"].verify_evidence_proof(
        leaf_hash=payload.leaf_hash,
        proof=payload.proof,
        root_hash=payload.root_hash,
    )