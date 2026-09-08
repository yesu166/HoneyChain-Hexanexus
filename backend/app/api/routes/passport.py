from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request, status

from ...core.config import get_settings
from ...schemas import passport as passport_schemas
from ..rate_limit import check_rate

router = APIRouter(prefix="/api/v1/passport", tags=["passport"])


@router.get("/{subject_code}", response_model=passport_schemas.PassportResponse)
def get_passport(subject_code: str, request: Request) -> passport_schemas.PassportResponse:
    """Public, no-auth consumer passport.

    Read-only, PII-free. Rate limited to keep anonymous lookups sane.
    """
    settings = get_settings()
    client_key = _client_key(request)
    if not check_rate(client_key, limit_per_minute=settings.passport_rate_limit_per_minute):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many lookups. Please try again later.",
        )

    payload = request.app.state.services["passport"].resolve(subject_code)
    if payload is None:
        raise HTTPException(status_code=404, detail="Product not found")

    response = passport_schemas.PassportResponse(
        **{k: v for k, v in payload.items() if k in passport_schemas.PassportResponse.model_fields}
    )
    response.raw = payload
    return response


def _client_key(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for", "")
    return forwarded.split(",")[0].strip() or request.client.host if request.client else "anon"