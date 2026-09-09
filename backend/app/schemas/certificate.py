from __future__ import annotations

from typing import Any, Literal, Optional

from pydantic import BaseModel, Field


class CertificateIssue(BaseModel):
    batch_id: str = Field(..., min_length=1)
    lab_id: str = "LAB-TN-001"
    certificate_type: str = "analysis"
    issued_at: str = ""
    valid_until: str = ""
    issuer_name: str = ""
    meta: dict[str, Any] = {}
    anchor: bool = True


class CertificateRevoke(BaseModel):
    reason: str = Field(..., min_length=1)
    actor_ref: str = ""


class CertificateVerify(BaseModel):
    certificate_id: str


class CertificateRead(BaseModel):
    certificate_id: str
    batch_id: str
    lab_id: str
    certificate_type: str
    issued_at: str = ""
    valid_until: str = ""
    content_hash: str = ""
    issuer_name: str = ""
    status: Literal["active", "revoked"] = "active"
    revoked_at: str = ""
    revocation_reason: str = ""
    anchor: dict[str, Any] = {}