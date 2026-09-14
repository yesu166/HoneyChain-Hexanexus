from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field


class LabTestCreate(BaseModel):
    batch_id: str = Field(..., min_length=1)
    lab_id: str = ""
    requested_note: str = ""


class LabResultSubmit(BaseModel):
    result: Literal["PASS", "FAIL"]
    tested_by: str = ""
    notes: str = ""


class LabTestRead(BaseModel):
    id: str
    batch_id: str
    lab_id: str
    status: Literal["requested", "in_progress", "passed", "failed"]
    result: Optional[str] = None
    requested_note: str = ""
    tested_by: str = ""
    requested_at: Optional[datetime] = None
    tested_at: Optional[datetime] = None


class LabQueueItem(LabTestRead):
    batch_code: str = ""
    honey_type: str = ""