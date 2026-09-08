from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class HarvestCreate(BaseModel):
    hive_id: str = Field(..., min_length=1)
    beekeeper_id: str = ""
    harvested_at: Optional[datetime] = None
    quantity_kg: float = Field(..., gt=0)
    honey_type: str = "Not specified"
    client_id: str = ""


class HarvestRead(BaseModel):
    id: str
    hive_id: str
    beekeeper_id: str
    harvested_at: datetime
    quantity_kg: float
    honey_type: str
    client_id: str = ""
    collected: bool = False