from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.security import get_current_user
from ...schemas import auth as auth_schema
from ...services.auth_service import AuthService

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


def _auth_service(request: Request) -> AuthService:
    return AuthService(request.app.state.repository)


@router.post("/login", response_model=auth_schema.TokenResponse)
def login(payload: auth_schema.LoginRequest, request: Request) -> dict[str, Any]:
    result = _auth_service(request).login(payload.identifier, payload.password)
    if "error" in result:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail=result["error"]
        )
    return result


@router.get("/me", response_model=auth_schema.UserMe)
def me(user: Any = Depends(get_current_user), request: Request = None) -> dict[str, Any]:
    profile = _auth_service(request).me(user.user_id)
    if profile is None:
        raise HTTPException(status_code=404, detail="User not found")
    return profile


@router.post("/register", response_model=auth_schema.UserMe, status_code=201)
def register(
    payload: auth_schema.RegisterUserRequest, request: Request
) -> dict[str, Any]:
    result = _auth_service(request).register(payload.model_dump())
    if "error" in result:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=result["error"])
    return result