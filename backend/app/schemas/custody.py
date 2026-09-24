from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field

CustodyAction = Literal[
    "HARVEST",
    "COLLECTION",
    "QUALITY_TEST",
    "PROCESSING",
    "PACKAGING",
    "TRANSFER",
    "DISTRIBUTION",
    "SALE",
    "CORRECTION",
]


class CustodyEventCreate(BaseModel):
    batch_id: str = Field(..., min_length=1)
    action: CustodyAction
    actor: str = ""
    notes: str = ""
    event_at: Optional[datetime] = None
    # Handover semantics for TRANSFER events: who/org receives custody. The
    # receiving actor gains batch scope (can assert, record receipt) without
    # the batch's organization_id ever being rewritten.
    to_actor: str = ""
    to_org: str = ""
    quantity_kg: float | None = Field(default=None, gt=0)
    # Stable browser/mobile retry key, persisted in custody metadata.
    client_id: str = ""


class CustodyEventRead(BaseModel):
    id: str
    batch_id: str
    action: str
    actor: str = ""
    notes: str = ""
    event_at: datetime
    to_actor: str = ""
    to_org: str = ""
    quantity_kg: float | None = None
    client_id: str = ""