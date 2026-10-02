"""Schemas for market linkage, QR packages, and the mobile processing van.

These back capabilities inside existing surfaces (FPO Market Linkage, Buyer
Procurement, KVIC Field Officer van, QR reuse detection) — they are not separate
portals and introduce no new role.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Literal, Optional

from pydantic import BaseModel, Field

ListingStatus = Literal["OPEN", "RESERVED", "SOLD", "WITHDRAWN"]
OrderStatus = Literal[
    "REQUESTED", "ACCEPTED", "REJECTED", "FULFILLED", "CANCELLED"
]


# --------------------------------------------------------------- market ----
class ListingCreate(BaseModel):
    batch_id: str = Field(..., min_length=1)
    quantity_kg: float = Field(..., gt=0)
    price_per_kg: float = Field(..., gt=0)
    currency: str = "INR"
    notes: str = ""
    client_id: str = ""


class ListingRead(BaseModel):
    id: str
    batch_id: str
    seller_org_id: str = ""
    quantity_kg: float
    remaining_kg: float
    price_per_kg: float
    currency: str = "INR"
    status: ListingStatus = "OPEN"
    notes: str = ""
    listed_at: Optional[datetime] = None
    closed_at: Optional[datetime] = None
    client_id: str = ""
    # Batch facts joined in by the service from the real batch row.
    batch_code: str = ""
    batch_origin: str = ""
    batch_honey_type: str = ""
    batch_trust_tier: str = ""
    batch_status: str = ""


class OrderCreate(BaseModel):
    listing_id: str = Field(..., min_length=1)
    quantity_kg: float = Field(..., gt=0)
    buyer_notes: str = ""
    client_id: str = ""


class OrderDecision(BaseModel):
    accept: bool
    seller_notes: str = ""


class OrderRead(BaseModel):
    id: str
    listing_id: str
    batch_id: str
    buyer_org_id: str = ""
    buyer_user_id: str = ""
    quantity_kg: float
    price_per_kg: float
    total_amount: float
    currency: str = "INR"
    status: OrderStatus = "REQUESTED"
    buyer_notes: str = ""
    seller_notes: str = ""
    requested_at: Optional[datetime] = None
    decided_at: Optional[datetime] = None
    decided_by: str = ""
    fulfilled_at: Optional[datetime] = None
    client_id: str = ""
    batch_code: str = ""
    batch_origin: str = ""
    batch_trust_tier: str = ""
    seller_org_id: str = ""


class MarketplaceRead(BaseModel):
    listings: list[ListingRead]
    orders: list[OrderRead]


# -------------------------------------------------------------------- QR ----
class PackageIssue(BaseModel):
    batch_id: str = Field(..., min_length=1)
    quantity_kg: float = Field(..., gt=0)
    # Optional explicit code. Supplying one is how a re-print is detected: the
    # second label with the same code resolves to the package that already owns
    # that identity rather than creating a second package.
    package_code: str = ""
    client_id: str = ""


class PackageRead(BaseModel):
    id: str
    package_code: str
    batch_id: str
    organization_id: str = ""
    quantity_kg: float
    status: str = "ACTIVE"
    first_scan_org: str = ""
    first_scan_at: Optional[datetime] = None
    scan_count: int = 0
    issued_at: Optional[datetime] = None
    client_id: str = ""


class QrScanRequest(BaseModel):
    package_code: str = Field(..., min_length=1)


class QrSignal(BaseModel):
    code: str
    detail: str = ""


class QrScanRecord(BaseModel):
    id: str
    package_code: str
    batch_id: Optional[str] = None
    scanner_user_id: str = ""
    scanner_role: str = ""
    organization_id: str = ""
    result: str = "CLEAR"
    signals: list[Any] = []
    scanned_at: Optional[datetime] = None


class QrScanRead(BaseModel):
    package: Optional[PackageRead] = None
    result: Literal["CLEAR", "SUSPICIOUS"]
    signals: list[QrSignal] = []
    prior_scan_count: int = 0
    # The persisted scan row. Returned so the caller (and the test) can confirm
    # the record actually exists rather than trusting an in-memory verdict.
    scan: Optional[QrScanRecord] = None


# ------------------------------------------------------------------- van ----
VanVisitStatus = Literal[
    "SCHEDULED", "ARRIVED", "SAMPLE_COLLECTED", "COMPLETED", "CANCELLED"
]
VanResult = Literal["PENDING", "PASS", "FAIL"]


class VanVisitCreate(BaseModel):
    van_code: str = Field(..., min_length=1, max_length=64)
    target_org_id: str = ""
    target_name: str = ""
    scheduled_for: Optional[datetime] = None
    notes: str = ""
    client_id: str = ""


class VanVisitRead(BaseModel):
    id: str
    van_code: str
    officer_user_id: str = ""
    organization_id: str = ""
    target_org_id: str = ""
    target_name: str = ""
    status: VanVisitStatus = "SCHEDULED"
    scheduled_for: Optional[datetime] = None
    arrived_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    notes: str = ""
    client_id: str = ""
    samples: list["VanSampleRead"] = []


class VanSampleCreate(BaseModel):
    batch_id: str = Field(..., min_length=1)
    sample_code: str = Field(..., min_length=1, max_length=64)
    quantity_kg: Optional[float] = Field(default=None, gt=0)
    moisture_percent: Optional[float] = Field(default=None, ge=0, le=100)
    notes: str = ""
    client_id: str = ""


class VanSampleRead(BaseModel):
    id: str
    visit_id: str
    batch_id: Optional[str] = None
    sample_code: str
    quantity_kg: Optional[float] = None
    result: VanResult = "PENDING"
    moisture_percent: Optional[float] = None
    notes: str = ""
    collected_at: Optional[datetime] = None
    client_id: str = ""
    # Van observations are explicitly NOT laboratory certificates, and the API
    # says so on every result so no surface can present one as the other.
    is_laboratory_certificate: bool = False
    batch_trust_tier: str = ""


class VanSampleResult(BaseModel):
    result: Literal["PASS", "FAIL"]
    notes: str = ""


class VanDashboardRead(BaseModel):
    visits: list[VanVisitRead]
    counts: dict[str, int] = {}


VanVisitRead.model_rebuild()
# QrScanRead references QrScanRecord, which FastAPI resolves lazily; an explicit
# rebuild keeps the annotation fully defined rather than deferring to first use.
QrScanRead.model_rebuild()