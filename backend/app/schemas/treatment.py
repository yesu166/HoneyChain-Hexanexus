from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class TreatmentCreate(BaseModel):
    hive_id: str
    treated_at: Optional[datetime] = None
    treatment_name: str
    active_ingredient: Optional[str] = None
    dosage: Optional[str] = None
    observation: Optional[str] = None
    status: str = "applied"
    client_id: str = ""


class TreatmentOut(BaseModel):
    id: str
    hive_id: str
    beekeeper_id: str
    treated_at: Optional[datetime] = None
    treatment_name: str
    active_ingredient: Optional[str] = None
    dosage: Optional[str] = None
    observation: Optional[str] = None
    status: str = "applied"
    client_id: str = ""