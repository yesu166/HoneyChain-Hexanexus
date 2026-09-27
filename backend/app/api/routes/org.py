from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request

from ...core.rbac import require_permission
from ...schemas import org as org_schemas
from ...services.org_service import OrgService

router = APIRouter(prefix="/api/v1", tags=["org"])


def _org_service(request: Request) -> OrgService:
    return OrgService(request.app.state.repository)


def _canonical_org_id(repo, org_ref: str) -> str:
    """Resolve either the organization UUID or public ORG-xxxxxx key."""
    ref = str(org_ref or "").strip()
    if not ref:
        return ""
    direct = repo.get_organization(ref)
    if direct:
        return str(direct.get("id") or ref)
    for org in repo.list_organizations():
        if str(org.get("id") or "") == ref or str(org.get("organization_key") or "") == ref:
            return str(org.get("id") or ref)
    return ""


@router.get("/org/{org_id}/dashboard", response_model=org_schemas.OrgDashboardRead)
def org_dashboard(
    org_id: str,
    request: Request,
    user=Depends(require_permission("org.dashboard")),
) -> dict:
    repo = request.app.state.repository
    target_org_id = _canonical_org_id(repo, org_id)
    if not target_org_id:
        raise HTTPException(status_code=404, detail="organization not found")

    # Scope: an org-bound caller may only read its own org's dashboard. The
    # caller and route may use either the UUID or the public ORG-xxxxxx key;
    # compare canonical organization IDs so the two representations cannot
    # accidentally cause a false 403.
    if user.role not in ("admin", "institution"):
        caller_org_id = _canonical_org_id(repo, user.org_id)
        if not caller_org_id or caller_org_id != target_org_id:
            raise HTTPException(status_code=403, detail="org is not in your scope")

    return _org_service(request).dashboard(target_org_id, response_org_id=org_id)


@router.get("/platform/stats", response_model=org_schemas.PlatformStatsRead)
def platform_stats(
    request: Request, user=Depends(require_permission("platform.stats"))
) -> dict:
    """Platform-wide aggregates — privileged read, clearly labeled aggregate."""
    return _org_service(request).platform_stats()