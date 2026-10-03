"""Restricted ASGI app that serves ONLY the Fabric bridge.

Why this exists
---------------
Until now the "only three /internal/fabric/* paths" rule was enforced in exactly
one place: the Caddy path matcher in front of the EC2 instance. The FastAPI app
on :8000 has always mounted the *entire* HoneyChain API (auth, hives, batches,
passports, platform orgs, AI chat) next to the bridge router — see app/main.py.
Port 8000 was safe only because the EC2 Security Group never allowed inbound
8000, and because Caddy 404'd everything else.

That protection is Caddy-dependent. Any transport that reaches the local port
directly — a Cloudflare Quick Tunnel (`cloudflared tunnel --url
http://127.0.0.1:8000`), a second reverse proxy, a mis-edited security group —
publishes the whole HoneyChain API, including open self-registration at
/api/v1/auth/register.

So the boundary moves into the application. This app mounts one router and
nothing else; every other path is FastAPI's default 404. It is meant to be run
as its own loopback-only uvicorn service, separate from the main API app, and to
be the sole target of any external tunnel:

    uvicorn app.bridge_app:app --host 127.0.0.1 --port 8001

The main app (app.main:app) is untouched and keeps serving the public API on
:8000. Caddy may still front :8001 instead; either way the allowlist is now
enforced by the application rather than by the edge.

Authentication is unchanged: internal_fabric._require_service_auth still
requires the constant-time FABRIC_BRIDGE_TOKEN bearer check, still refuses
everything when the secret is unset, and still refuses to serve unless the
Fabric adapter is genuinely active.
"""
from __future__ import annotations

from fastapi import FastAPI

from .api.routes import internal_fabric

app = FastAPI(
    title="HoneyChain Fabric bridge (restricted)",
    version="1.0.0",
    # No interactive surface: the bridge is a machine-to-machine endpoint, and
    # exposing schema docs here would be the same mistake as exposing the API.
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)

# The one and only router. Exactly three paths exist on this app:
#   GET  /internal/fabric/health
#   POST /internal/fabric/anchor
#   POST /internal/fabric/query
# Everything else 404s by FastAPI default.
app.include_router(internal_fabric.router)