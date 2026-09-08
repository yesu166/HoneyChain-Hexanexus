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


class CustodyEventRead(BaseModel):
    id: str
    batch_id: str
    action: str
    actor: str = ""
    notes: str = ""
    event_at: datetime