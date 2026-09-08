from __future__ import annotations

import time
from typing import Any

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .adapters.ai.base import build_risk_engine
from .adapters.blockchain.base import build_blockchain_adapter
from .api.deps import build_services_live
from .api.routes import auth, batches, custody, harvests, health, hives, labs, passport, sync
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


@app.on_event("startup")
def _startup() -> None:
    settings = get_settings()
    repo = build_repository()
    bootstrap_identities(repo)
    app.state.repository = repo
    app.state.services = build_services_live(repo)
    app.state.blockchain = build_blockchain_adapter(settings.blockchain_adapter)
    app.state.risk_engine = build_risk_engine(settings.ai_adapter)
    app.state.settings = settings
    log.info(
        "HoneyChain API started | env=%s | db=%s | blockchain=%s | ai=%s",
        settings.api_env,
        type(repo).__name__,
        settings.blockchain_adapter,
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
    hives.router,
    harvests.router,
    batches.router,
    labs.router,
    custody.router,
    passport.router,
    sync.router,
):
    app.include_router(router)


@app.get("/health")
async def liveness() -> dict[str, str]:
    return {"status": "ok", "service": "honeychain-api"}