from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request

from ...core.security import get_current_user
from ...schemas import sync as sync_schemas

router = APIRouter(prefix="/api/v1/sync", tags=["sync"])


@router.post("/push", response_model=sync_schemas.SyncPushResponse)
def sync_push(
    payload: dict, request: Request, user=Depends(get_current_user)
) -> dict:
    """Idempotent push. A client_id accepted once is never duplicated."""
    items = payload.get("items") or []
    if not isinstance(items, list) or len(items) > 500:
        raise HTTPException(status_code=422, detail="Expected items list (max 500)")
    accepted: list[sync_schemas.SyncAckItem] = []
    rejected: list[sync_schemas.SyncAckItem] = []
    sync = request.app.state.services["sync"]
    for raw_item in items:
        try:
            item = sync_schemas.SyncItem.model_validate(raw_item)
        except Exception as exc:  # schema validation failure
            rejected.append(
                sync_schemas.SyncAckItem(
                    entity=str(raw_item.get("entity") or "unknown"),
                    client_id=str(raw_item.get("client_id") or "unknown"),
                    accepted=False,
                    error=str(exc),
                )
            )
            continue
        result = sync.push_item(item.model_dump(), user=user)
        ack = sync_schemas.SyncAckItem(
            entity=item.entity,
            client_id=item.client_id,
            accepted=bool(result.get("accepted")),
            backend_id=result.get("backend_id", ""),
            error=result.get("error", ""),
        )
        (accepted if ack.accepted else rejected).append(ack)
    return {"accepted": accepted, "rejected": rejected}


@router.post("/pull", response_model=sync_schemas.SyncPullResponse)
def sync_pull(
    payload: sync_schemas.SyncPullRequest, request: Request, user=Depends(get_current_user)
) -> dict:
    items = request.app.state.services["sync"].pull(user=user)
    return {"items": items}