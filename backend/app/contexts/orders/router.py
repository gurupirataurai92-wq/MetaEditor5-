from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import AuthContext, get_auth, require
from app.contexts.identity.models import Shop, Tenant
from app.contexts.inventory.models import Product
from app.contexts.orders import service
from app.contexts.orders.models import Order, OrderLine

# Two routers: an unauthenticated public storefront and the staff-facing
# order management. Both are mounted under /api/v1.
public_router = APIRouter(prefix="/public", tags=["storefront"])
router = APIRouter(tags=["orders"])


# ------------------------------------------------------------ public schemas
class StoreProductOut(BaseModel):
    id: str
    name: str
    sell_price: Decimal
    currency: str


class StoreBranchOut(BaseModel):
    id: str
    name: str
    address: str | None


class StoreOut(BaseModel):
    business_name: str
    currency: str
    branches: list[StoreBranchOut]
    products: list[StoreProductOut]


class OrderItemIn(BaseModel):
    product_id: str
    qty: int = Field(gt=0)


class PlaceOrderIn(BaseModel):
    customer_name: str = Field(min_length=2, max_length=160)
    customer_phone: str = Field(min_length=5, max_length=32)
    customer_address: str | None = None
    fulfillment: str = "pickup"          # delivery|pickup
    shop_id: str | None = None
    payment_method: str = "cash"
    payment_reference: str | None = None
    note: str | None = None
    items: list[OrderItemIn]


class OrderLineOut(BaseModel):
    product_name: str
    qty: int
    unit_price: Decimal
    line_total: Decimal

    model_config = {"from_attributes": True}


class OrderOut(BaseModel):
    id: str
    number: str
    shop_id: str | None
    customer_name: str
    customer_phone: str
    customer_address: str | None
    fulfillment: str
    payment_method: str
    payment_reference: str | None
    note: str | None
    status: str
    subtotal: Decimal
    tax_amount: Decimal
    total: Decimal
    currency: str
    sale_id: str | None
    created_at: datetime
    lines: list[OrderLineOut]


def _order_out(db: Session, order: Order) -> OrderOut:
    lines = db.scalars(select(OrderLine).where(OrderLine.order_id == order.id)).all()
    return OrderOut(**{
        **{c: getattr(order, c) for c in OrderOut.model_fields if c != "lines"},
        "lines": [OrderLineOut.model_validate(l) for l in lines],
    })


# ------------------------------------------------------------ public routes
@public_router.get("/{tenant_id}/store", response_model=StoreOut)
def storefront(tenant_id: str, db: Session = Depends(get_db)):
    """Public catalogue for one business — no login required."""
    tenant = db.get(Tenant, tenant_id)
    if tenant is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Store not found")
    products = db.scalars(
        select(Product).where(Product.tenant_id == tenant_id, Product.is_active)
    ).all()
    branches = db.scalars(select(Shop).where(Shop.tenant_id == tenant_id)).all()
    return StoreOut(
        business_name=tenant.name,
        currency=tenant.base_currency,
        branches=[StoreBranchOut(id=s.id, name=s.name, address=s.address) for s in branches],
        products=[StoreProductOut(id=p.id, name=p.name, sell_price=p.sell_price,
                                  currency=p.currency) for p in products],
    )


@public_router.post("/{tenant_id}/orders", response_model=OrderOut, status_code=201)
def place_order(tenant_id: str, payload: PlaceOrderIn, db: Session = Depends(get_db)):
    if db.get(Tenant, tenant_id) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Store not found")
    order = service.place_order(db, tenant_id, payload)
    return _order_out(db, order)


@public_router.get("/{tenant_id}/orders/{order_id}", response_model=OrderOut)
def track_order(tenant_id: str, order_id: str, db: Session = Depends(get_db)):
    """Order tracking for the customer (they hold the opaque order id)."""
    return _order_out(db, service.get_order(db, tenant_id, order_id))


# ------------------------------------------------------------- staff routes
class OrderStatusIn(BaseModel):
    status: str = Field(pattern="^(confirmed|fulfilled|cancelled)$")


@router.get("/orders", response_model=list[OrderOut],
            dependencies=[Depends(require("orders.read"))])
def list_orders(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db),
                status_filter: str | None = None, shop_id: str | None = None,
                limit: int = 50):
    q = select(Order).where(Order.tenant_id == auth.tenant_id)
    if status_filter:
        q = q.where(Order.status == status_filter)
    if shop_id:
        q = q.where(Order.shop_id == shop_id)
    orders = db.scalars(q.order_by(Order.created_at.desc()).limit(min(limit, 200))).all()
    return [_order_out(db, o) for o in orders]


@router.patch("/orders/{order_id}", response_model=OrderOut,
              dependencies=[Depends(require("orders.update"))])
def update_order(order_id: str, payload: OrderStatusIn,
                 auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    order = service.update_status(db, auth.tenant_id, auth.user_id, order_id,
                                  payload.status)
    return _order_out(db, order)
