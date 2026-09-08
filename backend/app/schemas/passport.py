from __future__ import annotations

from datetime import datetime
from typing import Any, Literal, Optional

from pydantic import BaseModel

TrustTier = Literal[
    "self_declared",
    "organization_verified",
    "lab_verified",
    "blockchain_anchored",
]


class PassportEvent(BaseModel):
    type: str
    at: Optional[datetime] = None
    actor: str = ""
    detail: str = ""


class PassportVerification(BaseModel):
    lab_id: str = ""
    result: str = ""
    tested_by: str = ""
    tested_at: Optional[datetime] = None


class PassportAnchor(BaseModel):
    data_hash: str = ""
    tx_hash: str = ""
    chain_status: str = "none"
    anchored_at: Optional[datetime] = None


class PassportResponse(BaseModel):
    subject: Literal["batch", "product", "jar"]
    subject_code: str
    batch_code: str
    honey_type: str = ""
    origin: str = ""
    quantity_kg: float = 0
    trust_tier: TrustTier = "self_declared"
    events: list[PassportEvent] = []
    verification: Optional[PassportVerification] = None
    anchor: PassportAnchor = PassportAnchor()
    genealogy: list[str] = []
    caveat: str = (
        "Trust tiers reflect recorded evidence only. "
        "Blockchain anchoring provides tamper-evidence, not proof of purity. "
        "No health or nutrition claims are certified."
    )
    raw: dict[str, Any] = {}