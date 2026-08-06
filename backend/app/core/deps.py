"""Request-scoped auth context and RBAC dependencies."""
from dataclasses import dataclass

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.security import decode_token

_bearer = HTTPBearer(auto_error=False)


@dataclass
class AuthContext:
    user_id: str
    tenant_id: str
    role: str
    permissions: list[str]
    shop_id: str | None = None  # operator's home branch, if assigned


def get_auth(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> AuthContext:
    if creds is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not authenticated")
    payload = decode_token(creds.credentials)
    if payload is None or payload.get("type") != "access":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired token")
    return AuthContext(
        user_id=payload["sub"],
        tenant_id=payload["tid"],
        role=payload.get("role", ""),
        permissions=payload.get("perms", []),
        shop_id=payload.get("shop"),
    )


def permission_matches(required: str, granted: str) -> bool:
    if granted == "*" or granted == required:
        return True
    return granted.endswith(".*") and required.startswith(granted[:-1])


def require(permission: str):
    """RBAC gate: ``Depends(require("sales.create"))`` on any route."""

    def dependency(auth: AuthContext = Depends(get_auth)) -> AuthContext:
        if not any(permission_matches(permission, g) for g in auth.permissions):
            raise HTTPException(status.HTTP_403_FORBIDDEN, f"Missing permission: {permission}")
        return auth

    return dependency


def bind_tenant(db: Session, auth: AuthContext) -> None:
    """On PostgreSQL, bind the tenant for row-level security (defence in depth)."""
    if db.bind and db.bind.dialect.name == "postgresql":
        from sqlalchemy import text

        db.execute(text("SET app.tenant_id = :t"), {"t": auth.tenant_id})
