from __future__ import annotations

from datetime import datetime
from typing import Any, Literal, Optional

from pydantic import BaseModel, Field

AssertionNature = Literal["supporting", "adverse"]

AuthorityLevel = Literal[
    "SELF_DECLARED",
    "ORGANIZATION_VERIFIED",
    "LAB_VERIFIED",
    "AUTHORITY_VERIFIED",
    "PLATFORM_VERIFIED",
]

DiscrepancyState = Literal["UNDER_REVIEW", "RESOLVED", "UNRESOLVED"]


class AssertionCreate(BaseModel):
    """An evidence-linked assertion about a harvest or batch.

    `subject` is what the statement is ABOUT, which is what makes two
    organizations' claims comparable even when their actions differ.
    """

    entity_type: Literal["harvest", "batch"]
    entity_ref: str = Field(..., min_length=1)
    action: str = Field(..., min_length=2, max_length=32)
    subject: str = Field(..., min_length=2, max_length=32)
    # Missing quantity is never recorded as zero: for a quantity subject this
    # field is required by the service.
    asserted_quantity_kg: Optional[float] = None
    unit: str = "kg"
    organization_ref: str = ""
    note: str = ""
    nature: AssertionNature = "supporting"
    # When the offline client captured the event (local creation timestamp).
    captured_at: str = ""
    device_id: str = ""
    evidence_bundle_id: str = ""
    evidence_root: str = ""
    # Optional and clamped down server-side: a caller can never promote itself.
    declared_authority: Optional[AuthorityLevel] = None
    client_id: str = ""
    # Anchoring is opt-in and only applied where tamper-evidence is warranted.
    anchor: bool = False


class AssertionRead(BaseModel):
    assertion_id: str
    entity_type: str
    entity_ref: str
    action: str
    subject: str
    nature: str
    asserted_quantity_kg: Optional[float] = None
    quantity_asserted: bool = False
    unit: str = "kg"
    organization_ref: str = ""
    actor_ref: str = ""
    actor_role: str = ""
    authority: str = "SELF_DECLARED"
    authority_requested: str = ""
    authority_clamped: bool = False
    captured_at: str = ""
    recorded_at: str = ""
    note: str = ""
    evidence_bundle_id: str = ""
    evidence_root: str = ""
    evidence_linked: bool = False
    anchor: Optional[dict[str, Any]] = None
    anchor_state: str = "not_requested"
    ledger_hash: str = ""
    ledger_index: Optional[int] = None
    prev_hash: str = ""

    model_config = {"extra": "allow"}


class VerificationStateRead(BaseModel):
    entity_ref: str
    entity_type: str
    current_verification_level: str
    review_state: str
    dimensions: dict[str, bool]
    trust_tier_recorded: str = ""
    open_discrepancies: int = 0
    adverse_assertions: int = 0
    active_impacts: int = 0
    historical: list[dict[str, Any]] = []
    assertion_count: int = 0
    note: str = ""

    model_config = {"extra": "allow"}


class ReconcileRequest(BaseModel):
    subject: Optional[str] = None
    tolerance_kg: float = 0.01
    tolerance_pct: float = 0.005


class ResolveRequest(BaseModel):
    state: DiscrepancyState
    note: str = ""
    evidence_bundle_id: str = ""
    evidence_root: str = ""


class ImpactRequest(BaseModel):
    reason: str = Field(..., min_length=3, max_length=500)
    evidence_bundle_id: str = ""
    evidence_root: str = ""
    status: Literal["REVIEW_REQUIRED", "CLEARED", "CONFIRMED"] = "REVIEW_REQUIRED"


class ImpactRead(BaseModel):
    impact_id: str
    source: dict[str, Any]
    reason: str
    status: str
    evidence_root: str = ""
    affected: list[dict[str, Any]] = []
    affected_count: int = 0
    recorded: bool = False
    ledger_hashes: list[str] = []
    at: datetime | str | None = None

    model_config = {"extra": "allow"}