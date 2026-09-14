from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.rbac import require_permission
from ...schemas import org as org_schema
from ...services.platform_service import PlatformService

router = APIRouter(prefix="/api/v1/platform", tags=["platform-orgs"])


def _platform(request: Request) -> PlatformService:
    return request.app.state.services["platform"]


def _result_or_404(result: dict[str, Any]) -> dict[str, Any]:
    if "error" in result:
        raise HTTPException(status.HTTP_404_NOT_FOUND, result["error"])
    return result


@router.post(
    "/organizations",
    response_model=org_schema.OrganizationRead,
    status_code=status.HTTP_201_CREATED,
)
def create_organization(
    payload: org_schema.OrganizationCreate,
    request: Request,
    user: Any = Depends(require_permission("organization.create")),
) -> dict[str, Any]:
    result = _platform(request).create_fpo(data=payload.model_dump(), user=user)
    if "error" in result:
        raise HTTPException(status.HTTP_409_CONFLICT, result["error"])
    return result


@router.post(
    "/organizations/{org_key}/activate",
    response_model=org_schema.OrganizationRead,
)
def activate_organization(
    org_key: str,
    request: Request,
    user: Any = Depends(require_permission("organization.activate")),
) -> dict[str, Any]:
    return _result_or_404(_platform(request).activate_organization(org_key, user=user))


@router.post(
    "/organizations/{org_key}/suspend",
    response_model=org_schema.OrganizationRead,
)
def suspend_organization(
    org_key: str,
    request: Request,
    user: Any = Depends(require_permission("organization.suspend")),
) -> dict[str, Any]:
    return _result_or_404(_platform(request).suspend_organization(org_key, user=user))


@router.post(
    "/organizations/{org_key}/deactivate",
    response_model=org_schema.OrganizationRead,
)
def deactivate_organization(
    org_key: str,
    request: Request,
    user: Any = Depends(require_permission("organization.deactivate")),
) -> dict[str, Any]:
    return _result_or_404(_platform(request).deactivate_organization(org_key, user=user))


@router.post(
    "/organizations/{org_key}/admins",
    response_model=org_schema.OrganizationAdminInviteRead,
)
def onboard_initial_admin(
    org_key: str,
    payload: org_schema.OrganizationAdminInvite,
    request: Request,
    user: Any = Depends(require_permission("organization.onboard_admin")),
) -> dict[str, Any]:
    result = _platform(request).onboard_initial_admin(
        organization_key=org_key, email=payload.email, role=payload.role, user=user
    )
    return _result_or_404(result)


@router.post(
    "/organizations/{org_key}/admins/{invite_id}/revoke",
    response_model=org_schema.OrganizationAdminInviteRead,
)
def revoke_admin_invite(
    org_key: str,
    invite_id: str,
    request: Request,
    user: Any = Depends(require_permission("organization.revoke_admin")),
) -> dict[str, Any]:
    return _result_or_404(_platform(request).revoke_organization_invite(invite_id, user=user))


@router.get(
    "/organizations",
    response_model=list[org_schema.OrganizationRead],
)
def list_organizations(
    request: Request,
    user: Any = Depends(require_permission("organization.view_all")),
) -> list[dict[str, Any]]:
    return _platform(request).list_organizations()


# ------------------------------------------------------------------ membership
@router.post(
    "/organizations/{org_key}/beekeepers",
    status_code=status.HTTP_200_OK,
)
def assign_beekeeper(
    org_key: str,
    payload: org_schema.MemberAssign,
    request: Request,
    user: Any = Depends(require_permission("membership.assign")),
) -> dict[str, Any]:
    return _result_or_404(
        _platform(request).assign_beekeeper(
            org_key=org_key, user_id=payload.user_id, user=user
        )
    )


@router.post(
    "/organizations/{org_key}/members/{user_id}/revoke",
    status_code=status.HTTP_200_OK,
)
def revoke_membership(
    org_key: str,
    user_id: str,
    request: Request,
    user: Any = Depends(require_permission("membership.revoke")),
) -> dict[str, Any]:
    return _result_or_404(
        _platform(request).revoke_membership(org_key=org_key, user_id=user_id, user=user)
    )


@router.post(
    "/organizations/{org_key}/members/{user_id}/suspend",
    status_code=status.HTTP_200_OK,
)
def suspend_member(
    org_key: str,
    user_id: str,
    request: Request,
    user: Any = Depends(require_permission("member.suspend")),
) -> dict[str, Any]:
    return _result_or_404(
        _platform(request).suspend_member(org_key=org_key, user_id=user_id, user=user)
    )


@router.post(
    "/organizations/{org_key}/members/{user_id}/reinstate",
    status_code=status.HTTP_200_OK,
)
def reinstate_member(
    org_key: str,
    user_id: str,
    request: Request,
    user: Any = Depends(require_permission("member.reinstate")),
) -> dict[str, Any]:
    return _result_or_404(
        _platform(request).reinstate_member(org_key=org_key, user_id=user_id, user=user)
    )


@router.get(
    "/organizations/{org_key}/members",
    response_model=list[org_schema.OrganizationMemberRead],
)
def list_members(
    org_key: str,
    request: Request,
    user: Any = Depends(require_permission("membership.view")),
) -> list[dict[str, Any]]:
    return _platform(request).list_members(org_key)


@router.get(
    "/beekeepers",
    response_model=list[org_schema.BeekeeperPlatformRead],
)
def list_beekeepers(
    request: Request,
    user: Any = Depends(require_permission("membership.view")),
) -> list[dict[str, Any]]:
    org_key = request.query_params.get("org_key") or None
    return _platform(request).list_beekeepers(org_key)


@router.get(
    "/audit",
    response_model=list[org_schema.AuditEventRead],
)
def list_audit_events(
    request: Request,
    user: Any = Depends(require_permission("admin.audit")),
) -> list[dict[str, Any]]:
    limit = int(request.query_params.get("limit") or 100)
    return _platform(request).list_audit_events(limit=max(1, min(limit, 500)))