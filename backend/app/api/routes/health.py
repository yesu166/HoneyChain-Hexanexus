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


@router.get("/health/live")
async def health_live() -> dict[str, Any]:
    """Liveness: the process is up and serving requests."""
    return {"status": "ok", "service": "honeychain-api", "check": "live"}


@router.get("/health/ready")
async def health_ready(request: Request) -> dict[str, Any]:
    """Readiness: dependencies are reachable enough to serve traffic.

    Reports each dependency honestly — a dependency that is not configured
    (e.g. blockchain ledger in dev) is reported as such, not as healthy.
    """
    db_ok = _db_status(request.app.state.repository)
    gateway = request.app.state.services.get("gateway")
    adapter = gateway._adapter if gateway else None

    ledger_info: dict[str, Any] = {
        "name": gateway.ledger_name if gateway else "unknown",
        "status": "local",
    }

    # For Fabric: do a real query to determine connection status
    if adapter and hasattr(adapter, "health_check"):
        fabric_health = adapter.health_check()
        ledger_info = {
            "name": "fabric",
            "status": fabric_health.get("status", "unknown"),
            "channel": fabric_health.get("channel", ""),
            "chaincode": fabric_health.get("chaincode", ""),
            "chaincode_version": fabric_health.get("chaincode_version"),
            "peer": fabric_health.get("peer", ""),
            "last_verified_at": fabric_health.get("last_verified_at"),
            "error": fabric_health.get("error"),
        }

    overall = "ready" if db_ok == "ok" else "not_ready"
    if adapter and hasattr(adapter, "health_check"):
        fabric_ok = fabric_health.get("status") == "connected"
        overall = "ready" if db_ok == "ok" and fabric_ok else "not_ready"

    return {
        "status": overall,
        "service": "honeychain-api",
        "check": "ready",
        "dependencies": {
            "database": db_ok,
            "blockchain_ledger": ledger_info,
        },
    }