"""Notification/alert routes — derived state, never client-invented."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.rbac import require_permission
from ...schemas import notification as notif_schemas

router = APIRouter(prefix="/api/v1", tags=["notifications"])


@router.get("/notifications", response_model=notif_schemas.NotificationList)
def list_notifications(
    request: Request,
    limit: int = 50,
    user=Depends(require_permission("notification.read")),
) -> dict:
    service = request.app.state.services["notifications"]
    return service.list_for_user(user, limit=limit)


@router.post("/notifications/{notification_id}/read")
def mark_read(
    notification_id: str,
    request: Request,
    user=Depends(require_permission("notification.read")),
) -> dict:
    service = request.app.state.services["notifications"]
    try:
        row = service.mark_read(notification_id, user=user)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    if row is None:
        raise HTTPException(status_code=404, detail="notification not found")
    return row


@router.post("/notifications/stale-check")
def stale_check(
    request: Request,
    user=Depends(require_permission("iot.device.read")),
) -> dict:
    """Lazily evaluate every device's last_seen and raise staleness alerts for
    any device silent longer than 6 minutes. Returns the devices flagged."""
    service = request.app.state.services["notifications"]
    flagged = service.stale_devices()
    return {"flagged_devices": flagged, "count": len(flagged)}