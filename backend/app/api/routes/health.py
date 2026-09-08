from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, Request

from ...core.config import get_settings

router = APIRouter(tags=["health"])


def _db_status(repo: Any) -> str:
    try:
        repo.list_organizations()
        return "ok"
    except Exception:
        return "unavailable"


@router.get("/health")
@router.get("/api/v1/health")
async def health(request: Request) -> dict[str, Any]:
    """Deployment health check (no secrets)."""
    settings = get_settings()
    db_ok = _db_status(request.app.state.repository)
    return {
        "status": "ok" if db_ok == "ok" else "degraded",
        "service": "honeychain-api",
        "version": settings.api_version,
        "dependencies": {"database": db_ok},
    }