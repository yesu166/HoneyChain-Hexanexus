"""Exposure-boundary tests for the restricted bridge app (app.bridge_app).

The bridge is the only HoneyChain surface that may be reachable from outside the
host (Caddy, or a temporary Cloudflare Quick Tunnel). These tests pin the two
properties that make that safe:

  1. the three bridge paths exist,
  2. everything else is a 404 — in particular the entire HoneyChain API.

They are routing tests: they need no Fabric network, no database and no token.
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.bridge_app import app

BRIDGE_CALLS = (
    ("GET", "/internal/fabric/health", None),
    ("POST", "/internal/fabric/anchor", {"tx_ref": "boundary-test", "payload": {}}),
    ("POST", "/internal/fabric/query", {"op": "verify_anchor", "ref": "boundary-test"}),
)

# Paths that must never be reachable on the bridge host. The first group is the
# full public API; the rest are the interactive/doc surfaces.
FORBIDDEN_PATHS = (
    "/health",
    "/health/live",
    "/health/ready",
    "/api/v1/auth/login",
    "/api/v1/auth/register",
    "/api/v1/auth/me",
    "/api/v1/users",
    "/api/v1/hives",
    "/api/v1/batches",
    "/api/v1/passport/HC-2026-DEMO-001",
    "/api/v1/platform/organizations",
    "/api/v1/org/ORG-000001/dashboard",
    "/api/v1/ai/chat",
    "/api/v1/ai/status",
    "/api/v1/market/listings",
    "/api/v1/qr/scan",
    "/api/v1/blockchain/health",
    "/docs",
    "/redoc",
    "/openapi.json",
)


@pytest.fixture
def client():
    return TestClient(app, raise_server_exceptions=False)


@pytest.mark.parametrize("method,path,body", BRIDGE_CALLS)
def test_bridge_paths_are_routed(client, method, path, body):
    """The three bridge paths are served — never 404 — and never open.

    A routed call either authenticates or refuses. It never returns 404 (which
    would mean the path is missing) and never returns 200 (which would mean the
    credential check was skipped).
    """
    response = client.request(method, path, json=body)
    assert response.status_code != 404, f"{method} {path} must be routed on the bridge app"
    assert response.status_code in (401, 503), (
        f"{method} {path} must require the service credential, got {response.status_code}"
    )


@pytest.mark.parametrize("path", ("/internal/fabric/anchor", "/internal/fabric/query"))
def test_bridge_paths_reject_wrong_method(client, path):
    """A routed path answers 405 for the wrong verb, never 404 and never open."""
    assert client.get(path).status_code == 405


@pytest.mark.parametrize("path", FORBIDDEN_PATHS)
def test_general_api_is_not_exposed(client, path):
    """Nothing but the bridge may exist on the bridge app."""
    assert client.get(path).status_code == 404, f"{path} must 404 on the bridge app"


@pytest.mark.parametrize("path", FORBIDDEN_PATHS)
def test_general_api_is_not_exposed_on_post(client, path):
    """POST/other verbs are equally absent — the router is not merely GET-gated."""
    assert client.post(path, json={}).status_code == 404, (
        f"{path} must 404 on the bridge app for POST as well"
    )


def test_health_requires_the_service_credential(client, monkeypatch):
    """Bridge auth is unchanged: constant-time bearer check, never open."""
    monkeypatch.setenv("FABRIC_BRIDGE_TOKEN", "unit-test-secret-value")
    assert client.get("/internal/fabric/health").status_code == 401
    assert (
        client.get(
            "/internal/fabric/health",
            headers={"Authorization": "Bearer wrong-secret"},
        ).status_code
        == 401
    )


def test_unset_secret_refuses_everything(client, monkeypatch):
    """An unset secret must never degrade into an open endpoint."""
    monkeypatch.delenv("FABRIC_BRIDGE_TOKEN", raising=False)
    assert client.get("/internal/fabric/health").status_code == 503


def test_main_api_app_still_serves_the_public_api():
    """The boundary is enforced by the bridge app, not by crippling the main app."""
    from app.main import app as main_app

    # The context manager runs startup, which is what builds app.state.repository.
    with TestClient(main_app, raise_server_exceptions=False) as main_client:
        assert main_client.get("/health").status_code == 200