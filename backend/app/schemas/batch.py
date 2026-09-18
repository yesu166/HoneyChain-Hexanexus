from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field

TrustTier = Literal[
    "self_declared",
    "organization_verified",
    "lab_verified",
    "blockchain_anchored",
]


class HarvestAllocation(BaseModel):
    """Explicit share of one harvest consumed by a batch.

    Required for multi-harvest batches so a kilogram is never counted against
    two harvests at once. Single-harvest callers may omit it; the service then
    assigns the whole batch quantity to the lone harvest.
    """

    harvest_id: str = Field(..., min_length=1)
    quantity_kg: float = Field(..., gt=0)


class BatchCreate(BaseModel):
    batch_code: str = Field(..., min_length=1, max_length=64)
    organization_id: str = ""
    origin: str = ""
    honey_type: str = "Not specified"
    quantity_kg: float = Field(..., gt=0)
    harvest_ids: list[str] = []
    # Explicit per-harvest allocations. When supplied, each entry assigns part
    # of the batch quantity to one harvest. The entries must cover the whole
    # batch exactly, so the same kilogram can never be counted twice.
    harvest_allocations: list[HarvestAllocation] = []
    status: Optional[str] = None
    client_id: str = ""


class BatchRead(BaseModel):
    id: str
    batch_code: str
    status: str = "created"
    honey_type: str = "Not specified"
    quantity_kg: float
    origin: str = ""
    organization_id: str = ""
    trust_tier: TrustTier = "self_declared"
    created_at: Optional[datetime] = None
    client_id: str = ""


class BatchUpdate(BaseModel):
    status: Optional[str] = None
    honey_type: Optional[str] = None
    origin: Optional[str] = None


class GenealogyNode(BaseModel):
    id: str
    batch_code: str
    relationship: str  # root / SPLIT_FROM / AGGREGATED_FROM
    quantity_kg: float
    trust_tier: TrustTier = "self_declared"


class SplitRequest(BaseModel):
    child_quantities_kg: list[float] = Field(..., min_length=2, max_length=32)
    origin_hint: str = ""


class SplitResult(BaseModel):
    parent: BatchRead
    children: list[BatchRead]


class MergeRequest(BaseModel):
    batch_ids: list[str] = Field(..., min_length=2, max_length=32)
    new_batch_code: str = Field(..., min_length=1, max_length=64)


class MergeResult(BaseModel):
    merged: BatchRead
    sources: list[BatchRead]