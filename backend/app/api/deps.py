from __future__ import annotations

from typing import Any

from fastapi import Request

from ..db.supabase import Repository
from ..services.sync_service import build_services


def get_repo(request: Request) -> Repository:
    return request.app.state.repository


def get_services(request: Request) -> dict[str, Any]:
    return request.app.state.services


def get_service(request: Request, name: str) -> Any:
    return request.app.state.services[name]


def get_blockchain(request: Request) -> Any:
    return request.app.state.blockchain


def get_risk_engine(request: Request) -> Any:
    return request.app.state.risk_engine


def build_services_live(repo: Repository, gateway: Any = None) -> dict[str, Any]:
    return build_services(repo, gateway)