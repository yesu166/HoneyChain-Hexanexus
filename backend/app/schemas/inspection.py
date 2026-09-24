from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class InspectionCreate(BaseModel):
    hive_id: str
    inspected_at: Optional[datetime] = None
    activity_level: Optional[str] = None  # none | low | normal | high
    queen_seen: Optional[bool] = None
    brood_seen: Optional[bool] = None
    food_stores: Optional[str] = None  # plenty | enough | low | running_out | none
    pests_seen: Optional[str] = None  # e.g. varroa, small hive beetle
    dead_bees_seen: Optional[bool] = None
    hive_condition: Optional[str] = None  # good | fair | poor
    observations: Optional[str] = None
    client_id: str = ""


class InspectionOut(BaseModel):
    id: str
    hive_id: str
    beekeeper_id: str
    inspected_at: Optional[datetime] = None
    activity_level: Optional[str] = None
    queen_seen: Optional[bool] = None
    brood_seen: Optional[bool] = None
    food_stores: Optional[str] = None
    pests_seen: Optional[str] = None
    dead_bees_seen: Optional[bool] = None
    hive_condition: Optional[str] = None
    observations: Optional[str] = None
    client_id: str = ""


class InspectionDelete(BaseModel):
    id: str
    confirm: bool = False