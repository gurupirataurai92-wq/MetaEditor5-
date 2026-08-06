from datetime import datetime
from decimal import Decimal

from sqlalchemy import DateTime, Integer, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, new_id, utcnow

Money = Numeric(18, 4)


class Order(Base):
    """An online order placed by a customer from home. Its lifecycle is
    pending → confirmed → fulfilled (or cancelled). Fulfilling an order turns
    it into a real Sale, so it flows into finance and per-branch inventory."""

    __tablename__ = "orders"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    shop_id: Mapped[str | None] = mapped_column(String(36))  # fulfilling branch
    number: Mapped[str] = mapped_column(String(12), index=True)  # human ref, e.g. ORD-7F3A
    customer_name: Mapped[str] = mapped_column(String(160))
    customer_phone: Mapped[str] = mapped_column(String(32))
    customer_address: Mapped[str | None] = mapped_column(String(255))
    fulfillment: Mapped[str] = mapped_column(String(16))  # delivery|pickup
    payment_method: Mapped[str] = mapped_column(String(16))  # cash|ecocash|onemoney|zipit|paynow
    payment_reference: Mapped[str | None] = mapped_column(String(64))
    note: Mapped[str | None] = mapped_column(String(255))
    status: Mapped[str] = mapped_column(String(16), default="pending")
    subtotal: Mapped[Decimal] = mapped_column(Money)
    tax_amount: Mapped[Decimal] = mapped_column(Money)
    total: Mapped[Decimal] = mapped_column(Money)
    currency: Mapped[str] = mapped_column(String(3), default="USD")
    sale_id: Mapped[str | None] = mapped_column(String(36))  # set once fulfilled
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class OrderLine(Base):
    __tablename__ = "order_lines"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    order_id: Mapped[str] = mapped_column(String(36), index=True)
    product_id: Mapped[str] = mapped_column(String(36))
    product_name: Mapped[str] = mapped_column(String(200))
    qty: Mapped[int] = mapped_column(Integer)
    unit_price: Mapped[Decimal] = mapped_column(Money)
    line_total: Mapped[Decimal] = mapped_column(Money)
