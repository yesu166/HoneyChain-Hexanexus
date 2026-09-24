from __future__ import annotations

import os
import time
from typing import Any

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .adapters.ai.base import build_risk_engine
from .adapters.ai.gemini import build_gemini_provider
from .adapters.blockchain.gateway import build_blockchain_gateway
from .api.deps import build_services_live
from .services.ai_chat_service import AIChatService
from .api.routes import (
    ai,
    auth,
    assertions,
    batches,
    blockchain,
    certificates,
    custody,
    evidence,
    harvests,
    health,
    hives,
    iot,
    labs,
    lineage,
    notifications,
    org,
    passport,
    platform_orgs,
    sync,
    tamper,
)
from .core.config import get_settings
from .core.logging import configure_logging, get_logger
from .db.supabase import build_repository
from .services.auth_service import bootstrap_identities

configure_logging()
log = get_logger("honeychain.api")

app = FastAPI(
    title="HoneyChain HC-3.0 API",
    version=get_settings().api_version,
    docs_url=None if get_settings().is_production else "/docs",
    redoc_url=None if get_settings().is_production else None,
)


@app.middleware("http")
async def _request_logging(request: Request, call_next: Any):
    start = time.perf_counter()
    response = await call_next(request)
    duration_ms = (time.perf_counter() - start) * 1000
    log.info(
        "%s %s -> %s (%.1fms)",
        request.method,
        request.url.path,
        response.status_code,
        duration_ms,
    )
    return response


@app.exception_handler(Exception)
async def _unhandled(request: Request, exc: Exception) -> JSONResponse:
    log.exception("unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


def _enforce_render_production(settings: Any) -> None:
    """Refuse to serve in development mode on the public Render host.

    Someone must set the non-secret env var API_ENV=production in the Render
    service's Environment (render.yaml only applies its `value:` entries when a
    service is created via Blueprint — a manually-created Web Service does not
    receive them). Without this guard the app would silently expose /docs and
    run with dev defaults behind a public HTTPS host.
    """
    if settings.is_production:
        return
    if isinstance(settings.api_env, str) and settings.api_env.lower() != "production":
        marker = any(
            os.getenv(name)
            for name in (
                "RENDER_INSTANCE_ID",
                "RENDER_SERVICE_ID",
                "RENDER_EXTERNAL_URL",
            )
        )
        if marker:
            raise RuntimeError(
                "Refusing to start in %r on Render. Set API_ENV=production in "
                "the Render service Environment (non-secret) and redeploy." % settings.api_env
            )


@app.on_event("startup")
def _startup() -> None:
    settings = get_settings()
    _enforce_render_production(settings)
    repo = build_repository()
    bootstrap_identities(repo)
    gateway = build_blockchain_gateway(settings)
    app.state.repository = repo
    app.state.services = build_services_live(repo, gateway)
    app.state.blockchain = gateway
    app.state.risk_engine = build_risk_engine(settings.ai_adapter)
    app.state.settings = settings
    app.state.ai_service = AIChatService(
        provider=build_gemini_provider(settings),
        services=app.state.services,
        risk_engine=app.state.risk_engine,
        settings=settings,
    )
    log.info(
        "HoneyChain API started | env=%s | db=%s | ledger=%s | ai=%s",
        settings.api_env,
        type(repo).__name__,
        gateway.ledger_name,
        settings.ai_adapter,
    )


settings = get_settings()
if settings.cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

for router in (
    health.router,
    auth.router,
    ai.router,
    hives.router,
    harvests.router,
    batches.router,
    labs.router,
    custody.router,
    passport.router,
    sync.router,
    evidence.router,
    certificates.router,
    lineage.router,
    blockchain.router,
    tamper.router,
    iot.router,
    notifications.router,
    org.router,
    platform_orgs.router,
    assertions.router,
):
    app.include_router(router)


@app.get("/health")
async def liveness() -> dict[str, str]:
    return {"status": "ok", "service": "honeychain-api"}