from __future__ import annotations

from typing import Any, Literal, Optional

from pydantic import BaseModel, Field

EvidenceKind = Literal[
    "photo", "gps", "timestamp", "operator_note", "lab_sheet", "other",
    "telemetry_reference",
]


class EvidenceItem(BaseModel):
    kind: EvidenceKind
    value: str = ""
    captured_at: str = ""
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    content_hash: str = ""


class EvidenceBundleCreate(BaseModel):
    entity_type: Literal["harvest", "batch"]
    entity_ref: str = Field(..., min_length=1)
    operator: str = ""
    device_id: str = ""
    anchor: bool = True
    include_telemetry: bool = False
    telemetry_limit: int = Field(default=50, ge=1, le=200)
    telemetry_hive_id: str = ""
    evidence: list[EvidenceItem] = Field(..., min_length=1)


class EvidenceProofVerify(BaseModel):
    leaf_hash: str = Field(..., min_length=1)
    root_hash: str = Field(..., min_length=1)
    proof: list[dict[str, Any]] = Field(...)


class EvidenceRead(BaseModel):
    bundle_id: str
    entity_type: str
    entity_ref: str
    operator: str = ""
    created_at: Optional[str] = None
    leaf_count: int = 0
    root_hash: str = ""
    anchor: dict[str, Any] = {}
    evidence: list[dict[str, Any]] = []


class EvidenceVerifyResult(BaseModel):
    bundle_id: str
    entity_type: Optional[str] = None
    entity_ref: Optional[str] = None
    root_hash: Optional[str] = None
    recomputed_root: Optional[str] = None
    evidence_intact: bool = False
    anchor_state: Any = None
    anchored: bool = False
    anchor_live: Optional[bool] = None
    evidence_count: int = 0