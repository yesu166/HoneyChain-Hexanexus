from __future__ import annotations

from typing import Any, Literal, Optional

from pydantic import BaseModel, Field

BatchState = Literal[
    "created",
    "in_harvest",
    "processing",
    "packaged",
    "in_qa",
    "distribution",
    "retail",
    "recalled",
    "rejected",
]


class StateTransition(BaseModel):
    batch_id: str = Field(..., min_length=1)
    to_state: BatchState
    note: str = ""
    actor_ref: str = ""


class CustodyMove(BaseModel):
    batch_id: str = Field(..., min_length=1)
    sender_ref: str = Field(..., min_length=1)
    receiver_ref: str = Field(..., min_length=1)
    quantity_kg: float = Field(..., gt=0)
    action: str = Field(..., min_length=1)
    actor_ref: str = ""


class LineageStateRead(BaseModel):
    batch_id: str
    from_state: str = ""
    status: str
    changed: bool = False