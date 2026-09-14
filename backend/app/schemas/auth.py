from __future__ import annotations

from typing import Optional

from pydantic import BaseModel, EmailStr, Field


class LoginRequest(BaseModel):
    identifier: str = Field(..., description="email or phone")
    password: str = Field(..., min_length=6)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in_minutes: int


class UserMe(BaseModel):
    id: str
    email: str
    name: str
    phone: str = ""
    role: str
    org_id: str = ""
    producer_id: str = ""
    org_name: str = ""
    status: str = "ACTIVE"


class RegisterUserRequest(BaseModel):
    """Public self-registration.

    `admin` and `institution` are deliberately NOT self-servable: operators
    provision privileged accounts through a private flow, not the public
    endpoint. Beekeepers receive a persistent HoneyChain Producer ID.
    """

    email: EmailStr
    name: str = Field(..., min_length=1)
    phone: str = ""
    password: str = Field(..., min_length=8)
    role: str = Field(..., pattern="^(beekeeper|fpo|lab|processor|buyer)$")
    org_id: str = ""
    org_name: str = ""
    invite_code: str = ""