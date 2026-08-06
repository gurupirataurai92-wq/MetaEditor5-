"""Online-order domain logic.

Prices and VAT are ALWAYS computed server-side from the catalogue — the
public storefront is untrusted, so a client-supplied price is never believed.
Fulfilling an order replays it through the same ``create_sale`` path the POS
uses, so an online sale lands in finance and per-branch inventory exactly
like an in-store one.
"""
import secrets
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import audit
from app.core.config import get_settings
from app.core.db import new_id
from app.core.money import money, vat_portion
from app.contexts.inventory.service import get_product
from app.contexts.orders.models import Order, OrderLine
from app.contexts.sales.schemas import PaymentIn, SaleIn, SaleLineIn
from app.contexts.sales.service import create_sale

VALID_FULFILMENT = {"delivery", "pickup"}
VALID_METHODS = {"cash", "ecocash", "onemoney", "zipit", "paynow"}
MAX_QTY_PER_LINE = 999


def place_order(db: Session, tenant_id: str, data) -> Order:
    if data.fulfillment not in VALID_FULFILMENT:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid fulfilment option")
    if data.payment_method not in VALID_METHODS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid payment method")
    if not data.items:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Your cart is empty")

    settings = get_settings()
    order_id = new_id()
    lines: list[OrderLine] = []
    subtotal = Decimal("0")
    tax_total = Decimal("0")
    for item in data.items:
        if item.qty < 1 or item.qty > MAX_QTY_PER_LINE:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid quantity")
        product = get_product(db, tenant_id, item.product_id)
        if product is None or not product.is_active:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "A product is unavailable")
        unit_price = money(product.sell_price)          # server price, not client's
        line_total = money(unit_price * item.qty)
        tax = (vat_portion(line_total, settings.vat_rate)
               if product.tax_class == "standard" else Decimal("0.00"))
        lines.append(OrderLine(
            tenant_id=tenant_id, order_id=order_id, product_id=product.id,
            product_name=product.name, qty=item.qty, unit_price=unit_price,
            line_total=line_total,
        ))
        subtotal += line_total
        tax_total += tax

    subtotal = money(subtotal)
    tax_total = money(tax_total)
    order = Order(
        id=order_id, tenant_id=tenant_id, shop_id=data.shop_id,
        number=f"ORD-{secrets.token_hex(2).upper()}",
        customer_name=data.customer_name, customer_phone=data.customer_phone,
        customer_address=data.customer_address, fulfillment=data.fulfillment,
        payment_method=data.payment_method, payment_reference=data.payment_reference,
        note=data.note, status="pending",
        subtotal=subtotal, tax_amount=tax_total, total=subtotal, currency="USD",
    )
    db.add(order)
    db.add_all(lines)
    audit.record(db, tenant_id=tenant_id, actor_id=None, action="place",
                 entity="order", entity_id=order_id,
                 data={"number": order.number, "total": str(order.total),
                       "customer": order.customer_name})
    db.commit()
    return order


def get_order(db: Session, tenant_id: str, order_id: str) -> Order:
    order = db.get(Order, order_id)
    if order is None or order.tenant_id != tenant_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Order not found")
    return order


ALLOWED_TRANSITIONS = {
    "pending": {"confirmed", "cancelled"},
    "confirmed": {"fulfilled", "cancelled"},
    "fulfilled": set(),
    "cancelled": set(),
}


def update_status(db: Session, tenant_id: str, actor_id: str, order_id: str,
                  new_status: str) -> Order:
    order = get_order(db, tenant_id, order_id)
    if new_status == order.status:
        return order
    if new_status not in ALLOWED_TRANSITIONS.get(order.status, set()):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"Cannot move an order from {order.status} to {new_status}")

    if new_status == "fulfilled":
        # Replay the order as a real sale → finance + per-branch inventory.
        lines = db.scalars(
            select(OrderLine).where(OrderLine.order_id == order.id)).all()
        sale_in = SaleIn(
            currency=order.currency,
            shop_id=order.shop_id,
            lines=[SaleLineIn(product_id=l.product_id, qty=l.qty,
                              unit_price=l.unit_price) for l in lines],
            payments=[PaymentIn(method=order.payment_method, amount=order.total,
                                reference=order.payment_reference)],
        )
        sale, _ = create_sale(db, tenant_id=tenant_id, cashier_id=actor_id,
                              payload=sale_in, allow_oversell=True,
                              default_shop_id=order.shop_id)
        order.sale_id = sale.id

    order.status = new_status
    audit.record(db, tenant_id=tenant_id, actor_id=actor_id, action="status",
                 entity="order", entity_id=order.id,
                 data={"status": new_status, "sale_id": order.sale_id})
    db.commit()
    return order
