from __future__ import annotations

import os

os.environ["API_ENV"] = "development"
os.environ["JWT_SECRET"] = "test-secret-for-ci"
os.environ["DEMO_PASSWORD"] = "test-demo-password-for-ci"
os.environ.pop("SUPABASE_URL", None)
os.environ.pop("SUPABASE_SERVICE_ROLE_KEY", None)
os.environ["BLOCKCHAIN_ADAPTER"] = "simulated"
os.environ["AI_ADAPTER"] = "risk_engine"
os.environ["PASSPORT_RATE_LIMIT_PER_MINUTE"] = "1000"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.core.config import get_settings  # noqa: E402
from app.core.security import create_access_token  # noqa: E402
from app.main import app  # noqa: E402

# config.py loads backend/.env at import time (real creds live there). Tests are
# allowed to run against the in-memory repository by default; the empty values
# here proactively pin that contract even when a developer .env exists. A live
# Supabase integration test sets these keys itself.
os.environ["SUPABASE_URL"] = ""
os.environ["SUPABASE_SERVICE_ROLE_KEY"] = ""

get_settings.cache_clear()

DEMO_EMAIL = "demo@honeychain.in"
DEMO_PASSWORD = "test-demo-password-for-ci"


def make_token(
    user_id: str, role: str, org_id: str = "", roles: list[str] | None = None, minutes: int = 30
) -> str:
    from datetime import timedelta

    return create_access_token(
        user_id, role, roles=roles, org_id=org_id, expires_delta=timedelta(minutes=minutes)
    )


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def client():
    get_settings.cache_clear()
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture()
def demo_token(client) -> str:
    return make_token("demo-beekeeper-id", "beekeeper", "ORG-TN-001")


@pytest.fixture()
def fpo_token(client) -> str:
    return make_token("fpo-user-id", "fpo", "ORG-TN-001")


@pytest.fixture()
def lab_token(client) -> str:
    return make_token("lab-user-id", "lab", "LAB-TN-001")


@pytest.fixture()
def admin_token(client) -> str:
    return make_token("admin-user-id", "admin")


@pytest.fixture()
def buyer_token(client) -> str:
    return make_token("buyer-user-id", "buyer")


@pytest.fixture()
def processor_token(client) -> str:
    return make_token("processor-user-id", "processor")