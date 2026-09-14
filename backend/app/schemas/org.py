from __future__ import annotations

from typing import Any, Literal, Optional

from pydantic import BaseModel, EmailStr, Field

OrganizationStatus = Literal["PENDING", "ACTIVE", "SUSPENDED", "DORMANT"]


class ActivityItem(BaseModel):
    type: str = "event"
    label: str = ""
    timestamp: str = ""
    entity_ref: str = ""


class OrgDashboardRead(BaseModel):
    org_id: str
    org_name: str = ""
    active_beekeepers: int = 0
    hives: int = 0
    clusters: int = 0
    honey_harvested_kg: float = 0.0
    collections: int = 0
    batches: int = 0
    verified_batches: int = 0
    pending_actions: int = 0
    recent_activity: list[ActivityItem] = []
    source: str = "backend"


class PlatformStatsRead(BaseModel):
    registered_beekeepers: int = 0
    organizations: int = 0
    hives: int = 0
    harvests: int = 0
    honey_harvested_kg: float = 0.0
    batches: int = 0
    lab_tests: int = 0
    certificates: int = 0
    iot_devices: int = 0
    telemetry_events: int = 0


class OrganizationCreate(BaseModel):
    """Platform-side FPO creation.

    The backend generates `id` (uuid) and `organization_key` server-side; a
    client must never supply or influence either.
    """

    name: str = Field(..., min_length=1, max_length=200)
    type: str = "FPO"
    country: str = ""
    state: str = ""
    district: str = ""
    address: str = ""
    postal_code: str = ""
    contact_email: str = ""
    contact_phone: str = ""
    registration_no: str = ""
    client_id: str = ""


class OrganizationRead(BaseModel):
    id: str = ""
    organization_key: str = ""
    name: str = ""
    type: str = "FPO"
    status: str = "PENDING"
    country: str = ""
    state: str = ""
    district: str = ""
    address: str = ""
    postal_code: str = ""
    contact_email: str = ""
    contact_phone: str = ""
    registration_no: str = ""
    location: str = ""
    client_id: str = ""


class OrganizationActionRead(BaseModel):
    id: str = ""
    organization_key: str = ""
    name: str = ""
    type: str = "FPO"
    status: str


class MemberAssign(BaseModel):
    """Assign an existing beekeeper user to an organization."""

    user_id: str = Field(..., min_length=1)


class OrganizationAdminInvite(BaseModel):
    """Issued by the platform to bootstrap an FPO's first admin account."""

    email: EmailStr
    role: str = "fpo"


class OrganizationAdminInviteRead(BaseModel):
    id: str = ""
    organization_key: str = ""
    email: str = ""
    role: str = "fpo"
    token: str = ""
    status: str = "PENDING"
    created_at: str = ""


class OrganizationMemberRead(BaseModel):
    id: str
    email: str = ""
    name: str = ""
    phone: str = ""
    role: str = ""
    org_id: str = ""
    status: str = "ACTIVE"
    producer_id: str = ""


class BeekeeperPlatformRead(BaseModel):
    id: str = ""
    name: str = ""
    phone: str = ""
    producer_id: str = ""
    organization_id: str = ""
    org_key: str = ""
    org_name: str = ""
    is_independent: bool = True
    client_id: str = ""


class AuditEventRead(BaseModel):
    id: str = ""
    actor_user_id: str = ""
    actor_role: str = ""
    action: str = ""
    target_type: str = ""
    target_key: str = ""
    detail: dict[str, Any] = {}
    created_at: str = ""