from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field


class SyncItem(BaseModel):
    entity: Literal[
        "hive", "harvest", "batch", "reading", "custody",
        "quantity_assertion", "assertion",
    ]
    client_id: str = Field(..., min_length=1)
    data: dict = Field(default_factory=dict)


class SyncPullRequest(BaseModel):
    since: Optional[str] = None
    scope: str = "mine"


class SyncAckItem(BaseModel):
    entity: str
    client_id: str
    accepted: bool
    backend_id: str = ""
    error: str = ""
    # True when this client_id was already accepted before (offline retry):
    # the server did NOT create a duplicate record.
    deduplicated: bool = False


class SyncPushResponse(BaseModel):
    accepted: list[SyncAckItem]
    rejected: list[SyncAckItem]


class SyncPullItem(BaseModel):
    entity: str
    backend_id: str
    client_id: str = ""
    data: dict
    updated_at: Optional[str] = None


class SyncPullResponse(BaseModel):
    items: list[SyncPullItem]