from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class HiveCreate(BaseModel):
    hive_code: str = Field(..., min_length=1, max_length=64)
    beekeeper_id: str = ""
    status: str = "active"
    client_id: str = ""
    location: Optional[str] = None


class HiveUpdate(BaseModel):
    hive_code: Optional[str] = None
    status: Optional[str] = None
    location: Optional[str] = None


class HiveRead(BaseModel):
    id: str
    hive_code: str
    beekeeper_id: str
    org_id: str = ""
    status: str = "active"
    created_at: Optional[datetime] = None
    client_id: str = ""


class ReadingCreate(BaseModel):
    temperature_c: Optional[float] = None
    humidity_percent: Optional[float] = None
    weight_kg: Optional[float] = None
    recorded_at: Optional[datetime] = None
    source: str = "manual"
    client_id: str = ""


class ReadingRead(BaseModel):
    id: str
    hive_id: str
    temperature_c: Optional[float] = None
    humidity_percent: Optional[float] = None
    weight_kg: Optional[float] = None
    recorded_at: Optional[datetime] = None
    source: str = "manual"


class RiskFactor(BaseModel):
    factor: str
    contribution: str


class HealthScoreOut(BaseModel):
    hive_id: str
    risk_level: str  # LOW / MEDIUM / HIGH
    risk_score: int  # 0..100 (higher = more stress)
    contributing_factors: list[RiskFactor] = []
    recommended_action: str
    simulated: bool = False
    timestamp: datetime