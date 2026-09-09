from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.security import get_current_user, require_roles
from ...schemas import certificate as cert_schemas

router = APIRouter(prefix="/api/v1", tags=["certificates"])


@router.post(
    "/certificates/issue",
    response_model=cert_schemas.CertificateRead,
)
def issue_certificate(
    payload: cert_schemas.CertificateIssue,
    request: Request,
    user=Depends(require_roles("lab", "admin")),
) -> dict:
    services = request.app.state.services
    try:
        certificate = services["certificates"].issue(
            batch_id=payload.batch_id,
            lab_id=payload.lab_id,
            certificate_type=payload.certificate_type,
            issued_at=payload.issued_at,
            valid_until=payload.valid_until,
            meta=payload.meta,
            issuer_name=payload.issuer_name,
            anchor=payload.anchor,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return certificate


@router.post(
    "/certificates/{certificate_id}/revoke",
    response_model=cert_schemas.CertificateRead,
)
def revoke_certificate(
    certificate_id: str,
    payload: cert_schemas.CertificateRevoke,
    request: Request,
    user=Depends(require_roles("lab", "admin")),
) -> dict:
    from ...services.lab_certificate import CertificateError

    try:
        return request.app.state.services["certificates"].revoke(
            certificate_id, reason=payload.reason, actor_ref=payload.actor_ref
        )
    except CertificateError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/certificates/verify/{certificate_id}")
def verify_certificate(certificate_id: str, request: Request) -> dict:
    return request.app.state.services["certificates"].verify(certificate_id)


@router.get(
    "/batches/{batch_id}/certificates",
    response_model=list[cert_schemas.CertificateRead],
)
def certificates_for_batch(batch_id: str, request: Request) -> list:
    return request.app.state.services["certificates"].for_batch(batch_id)