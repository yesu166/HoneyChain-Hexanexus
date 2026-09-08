from __future__ import annotations

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


class RegisterUserRequest(BaseModel):
    email: EmailStr
    name: str = Field(..., min_length=1)
    phone: str = ""
    password: str = Field(..., min_length=8)
    role: str = Field(..., pattern="^(beekeeper|fpo|lab|processor|admin|buyer)$")
    org_id: str = ""