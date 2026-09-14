from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request

from ...core.rbac import require_permission
from ...schemas import org as org_schemas
from ...services.org_service import OrgService

router = APIRouter(prefix="/api/v1", tags=["org"])


def _org_service(request: Request) -> OrgService:
    return OrgService(request.app.state.repository)


@router.get("/org/{org_id}/dashboard", response_model=org_schemas.OrgDashboardRead)
def org_dashboard(
    org_id: str,
    request: Request,
    user=Depends(require_permission("org.dashboard")),
) -> dict:
    # Scope: an org-bound caller may only read its own org's dashboard.
    if user.role not in ("admin", "institution") and user.org_id != org_id:
        raise HTTPException(status_code=403, detail="org is not in your scope")
    return _org_service(request).dashboard(org_id)


@router.get("/platform/stats", response_model=org_schemas.PlatformStatsRead)
def platform_stats(
    request: Request, user=Depends(require_permission("platform.stats"))
) -> dict:
    """Platform-wide aggregates — privileged read, clearly labeled aggregate."""
    return _org_service(request).platform_stats()