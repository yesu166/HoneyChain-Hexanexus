from __future__ import annotations

import pytest

from app.main import _enforce_render_production


def test_allows_production_on_render(monkeypatch):
    monkeypatch.setenv("RENDER_INSTANCE_ID", "abc-123")

    class S:
        api_env = "production"
        is_production = True

    _enforce_render_production(S())  # should not raise


def test_allows_development_off_render(monkeypatch):
    monkeypatch.delenv("RENDER_INSTANCE_ID", raising=False)
    monkeypatch.delenv("RENDER_SERVICE_ID", raising=False)
    monkeypatch.delenv("RENDER_EXTERNAL_URL", raising=False)

    class S:
        api_env = "development"
        is_production = False

    _enforce_render_production(S())


def test_refuses_development_on_render(monkeypatch):
    monkeypatch.setenv("RENDER_SERVICE_ID", "svc-42")

    class S:
        api_env = "development"
        is_production = False

    with pytest.raises(RuntimeError, match="API_ENV=production"):
        _enforce_render_production(S())