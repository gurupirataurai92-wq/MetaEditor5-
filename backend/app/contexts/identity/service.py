from datetime import timedelta

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import audit
from app.core.config import get_settings
from app.core.db import utcnow
from app.core.security import (
    create_access_token,
    hash_password,
    new_refresh_token,
    token_digest,
    verify_password,
    verify_totp,
)
from app.contexts.identity.models import RefreshToken, Role, Shop, Tenant, User
from app.contexts.identity.schemas import RegisterBusinessIn, UserCreateIn

# Default role → permission grants, seeded per tenant at registration.
# Grammar: "*" = everything; "sales.*" = every action in sales; else exact.
DEFAULT_ROLES: dict[str, list[str]] = {
    "owner": ["*"],
    "manager": [
        "products.*", "categories.*", "stock.*", "suppliers.*", "sales.*",
        "customers.*", "expenses.*", "rates.*", "reports.*", "analytics.*",
        "employees.*", "sync.*", "audit.read", "shops.read", "users.read",
        # Managers hire and remove staff (creating each employee's own login),
        # update goods prices, correct recorded payments and manage online
        # orders — but cannot open/delete branches or see owner financials.
        "users.create", "payments.*", "orders.*",
    ],
    "cashier": [
        "sales.create", "sales.read", "customers.read", "customers.create",
        # Till operators serve customers, may add/retire products and receive
        # stock, and fulfil online orders — but never see finance or reports.
        "products.read", "products.create", "products.update",
        "stock.read", "stock.create", "sync.*",
        "orders.read", "orders.update",
    ],
    "storekeeper": [
        "products.*", "categories.*", "stock.*", "suppliers.*", "sync.*",
    ],
    "accountant": [
        "reports.*", "expenses.*", "rates.*", "sales.read", "audit.read",
        "analytics.*", "orders.read",
    ],
}


def register_business(db: Session, data: RegisterBusinessIn) -> User:
    existing = db.scalar(select(User).where(User.email == data.email.lower()))
    if existing:
        raise HTTPException(status.HTTP_409_CONFLICT, "Email already registered")

    tenant = Tenant(name=data.business_name, base_currency=data.base_currency.upper())
    db.add(tenant)
    db.flush()

    shop = Shop(tenant_id=tenant.id, name="Main Shop")
    db.add(shop)

    roles = {
        name: Role(tenant_id=tenant.id, name=name, permissions=perms)
        for name, perms in DEFAULT_ROLES.items()
    }
    db.add_all(roles.values())
    db.flush()

    owner = User(
        tenant_id=tenant.id,
        shop_id=shop.id,
        email=data.email.lower(),
        full_name=data.full_name,
        password_hash=hash_password(data.password),
        role_id=roles["owner"].id,
    )
    db.add(owner)
    db.flush()
    audit.record(db, tenant_id=tenant.id, actor_id=owner.id, action="register",
                 entity="tenant", entity_id=tenant.id, data={"name": tenant.name})
    db.commit()
    return owner


def create_user(db: Session, tenant_id: str, actor_id: str, data: UserCreateIn) -> User:
    if db.scalar(select(User).where(User.email == data.email.lower())):
        raise HTTPException(status.HTTP_409_CONFLICT, "Email already registered")
    role = db.scalar(select(Role).where(Role.tenant_id == tenant_id, Role.name == data.role))
    if role is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, f"Unknown role: {data.role}")
    user = User(
        tenant_id=tenant_id,
        shop_id=data.shop_id,
        email=data.email.lower(),
        full_name=data.full_name,
        password_hash=hash_password(data.password),
        role_id=role.id,
    )
    db.add(user)
    db.flush()
    audit.record(db, tenant_id=tenant_id, actor_id=actor_id, action="create",
                 entity="user", entity_id=user.id, data={"email": user.email, "role": role.name})
    db.commit()
    return user


def get_role(db: Session, user: User) -> Role:
    role = db.get(Role, user.role_id)
    if role is None:  # defensive: roles are seeded with the tenant
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Role missing")
    return role


def issue_tokens(db: Session, user: User) -> dict:
    settings = get_settings()
    role = get_role(db, user)
    access = create_access_token(
        user_id=user.id, tenant_id=user.tenant_id,
        role=role.name, permissions=list(role.permissions), shop_id=user.shop_id,
    )
    refresh = new_refresh_token()
    db.add(RefreshToken(
        user_id=user.id,
        token_hash=token_digest(refresh),
        expires_at=utcnow() + timedelta(days=settings.refresh_token_ttl_days),
    ))
    db.commit()
    return {"access_token": access, "refresh_token": refresh}


def login(db: Session, email: str, password: str, totp_code: str | None) -> User:
    user = db.scalar(select(User).where(User.email == email.lower()))
    if user is None or not verify_password(password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid credentials")
    if not user.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Account disabled")
    if user.totp_enabled:
        if not totp_code:
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "2FA code required")
        if not user.totp_secret or not verify_totp(user.totp_secret, totp_code):
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid 2FA code")
    return user


def rotate_refresh(db: Session, token: str) -> User:
    row = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == token_digest(token)))
    if row is None or row.revoked or row.expires_at < utcnow():
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid refresh token")
    row.revoked = True  # single-use rotation
    user = db.get(User, row.user_id)
    if user is None or not user.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid refresh token")
    return user
