from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core import audit
from app.core.db import get_db
from app.core.deps import AuthContext, get_auth, require
from app.core.security import generate_totp_secret, otpauth_uri, verify_totp
from app.contexts.identity import service
from app.contexts.identity.models import Shop, User
from app.contexts.identity.schemas import (
    LoginIn,
    RefreshIn,
    RegisterBusinessIn,
    ShopIn,
    ShopOut,
    TokenPairOut,
    TwoFAEnableIn,
    TwoFASetupOut,
    UserCreateIn,
    UserOut,
)

router = APIRouter(tags=["identity"])


def _user_out(db: Session, user: User) -> UserOut:
    return UserOut(
        id=user.id, tenant_id=user.tenant_id, email=user.email,
        full_name=user.full_name, role=service.get_role(db, user).name,
        totp_enabled=user.totp_enabled, is_active=user.is_active,
    )


@router.post("/auth/register-business", response_model=TokenPairOut, status_code=201)
def register_business(payload: RegisterBusinessIn, db: Session = Depends(get_db)):
    user = service.register_business(db, payload)
    return service.issue_tokens(db, user)


@router.post("/auth/login", response_model=TokenPairOut)
def login(payload: LoginIn, db: Session = Depends(get_db)):
    user = service.login(db, payload.email, payload.password, payload.totp_code)
    return service.issue_tokens(db, user)


@router.post("/auth/refresh", response_model=TokenPairOut)
def refresh(payload: RefreshIn, db: Session = Depends(get_db)):
    user = service.rotate_refresh(db, payload.refresh_token)
    return service.issue_tokens(db, user)


@router.get("/auth/me", response_model=UserOut)
def me(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    user = db.get(User, auth.user_id)
    if user is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
    return _user_out(db, user)


@router.post("/auth/2fa/setup", response_model=TwoFASetupOut)
def setup_2fa(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    user = db.get(User, auth.user_id)
    user.totp_secret = generate_totp_secret()
    db.commit()
    return TwoFASetupOut(secret=user.totp_secret,
                         otpauth_uri=otpauth_uri(user.totp_secret, user.email))


@router.post("/auth/2fa/enable")
def enable_2fa(payload: TwoFAEnableIn, auth: AuthContext = Depends(get_auth),
               db: Session = Depends(get_db)):
    user = db.get(User, auth.user_id)
    if not user.totp_secret or not verify_totp(user.totp_secret, payload.code):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid 2FA code")
    user.totp_enabled = True
    db.commit()
    return {"enabled": True}


@router.post("/users", response_model=UserOut, status_code=201,
             dependencies=[Depends(require("users.create"))])
def create_user(payload: UserCreateIn, auth: AuthContext = Depends(get_auth),
                db: Session = Depends(get_db)):
    user = service.create_user(db, auth.tenant_id, auth.user_id, payload)
    return _user_out(db, user)


@router.get("/users", response_model=list[UserOut],
            dependencies=[Depends(require("users.read"))])
def list_users(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    users = db.scalars(select(User).where(User.tenant_id == auth.tenant_id)).all()
    return [_user_out(db, u) for u in users]


@router.post("/shops", response_model=ShopOut, status_code=201,
             dependencies=[Depends(require("shops.create"))])
def create_shop(payload: ShopIn, auth: AuthContext = Depends(get_auth),
                db: Session = Depends(get_db)):
    shop = Shop(tenant_id=auth.tenant_id, name=payload.name, address=payload.address)
    db.add(shop)
    db.commit()
    return ShopOut(id=shop.id, name=shop.name, address=shop.address)


@router.get("/shops", response_model=list[ShopOut],
            dependencies=[Depends(require("shops.read"))])
def list_shops(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    shops = db.scalars(select(Shop).where(Shop.tenant_id == auth.tenant_id)).all()
    return [ShopOut(id=s.id, name=s.name, address=s.address) for s in shops]


@router.delete("/shops/{shop_id}", status_code=204,
               dependencies=[Depends(require("shops.delete"))])
def delete_shop(shop_id: str, auth: AuthContext = Depends(get_auth),
                db: Session = Depends(get_db)):
    """Close a branch (owner only). Historical sales keep their shop_id for the
    audit trail; staff assigned there are unassigned."""
    from app.contexts.hr.models import Employee

    shop = db.get(Shop, shop_id)
    if shop is None or shop.tenant_id != auth.tenant_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Branch not found")
    remaining = db.scalar(
        select(func.count()).select_from(Shop).where(Shop.tenant_id == auth.tenant_id))
    if remaining <= 1:
        raise HTTPException(status.HTTP_400_BAD_REQUEST,
                            "Cannot delete the only branch")
    for emp in db.scalars(select(Employee).where(Employee.shop_id == shop_id)).all():
        emp.shop_id = None
    db.delete(shop)
    audit.record(db, tenant_id=auth.tenant_id, actor_id=auth.user_id, action="delete",
                 entity="shop", entity_id=shop_id, data={"name": shop.name})
    db.commit()
