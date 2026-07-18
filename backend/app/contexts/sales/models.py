from datetime import datetime
from decimal import Decimal

from sqlalchemy import BigInteger, DateTime, Integer, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, new_id, utcnow

Money = Numeric(18, 4)
Rate = Numeric(18, 6)


class Customer(Base):
    __tablename__ = "customers"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    name: Mapped[str] = mapped_column(String(160))
    phone: Mapped[str | None] = mapped_column(String(32))
    email: Mapped[str | None] = mapped_column(String(255))
    loyalty_points: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Sale(Base):
    """Immutable sale event. ``id`` is client-generated (UUID) so replays and
    offline sync retries are idempotent; voiding appends a reversal rather
    than deleting history."""

    __tablename__ = "sales"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)  # client-generated
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    shop_id: Mapped[str | None] = mapped_column(String(36))
    customer_id: Mapped[str | None] = mapped_column(String(36))
    cashier_id: Mapped[str] = mapped_column(String(36))
    subtotal: Mapped[Decimal] = mapped_column(Money)      # net of VAT
    tax_amount: Mapped[Decimal] = mapped_column(Money)    # VAT portion (inclusive pricing)
    total: Mapped[Decimal] = mapped_column(Money)         # gross, in `currency`
    currency: Mapped[str] = mapped_column(String(3))
    base_currency: Mapped[str] = mapped_column(String(3))
    exchange_rate: Mapped[Decimal] = mapped_column(Rate)  # base per 1 unit of currency
    rate_source: Mapped[str] = mapped_column(String(32), default="manual")
    status: Mapped[str] = mapped_column(String(16), default="committed")  # committed|void
    note: Mapped[str | None] = mapped_column(String(255))
    captured_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    synced_at: Mapped[datetime | None] = mapped_column(DateTime)
    lamport: Mapped[int] = mapped_column(BigInteger, default=0)


class SaleLine(Base):
    __tablename__ = "sale_lines"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    sale_id: Mapped[str] = mapped_column(String(36), index=True)
    product_id: Mapped[str] = mapped_column(String(36))
    product_name: Mapped[str] = mapped_column(String(200))  # denormalised for receipts
    qty: Mapped[int] = mapped_column(Integer)
    unit_price: Mapped[Decimal] = mapped_column(Money)
    line_total: Mapped[Decimal] = mapped_column(Money)
    tax_amount: Mapped[Decimal] = mapped_column(Money)


class Payment(Base):
    __tablename__ = "payments"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    sale_id: Mapped[str] = mapped_column(String(36), index=True)
    method: Mapped[str] = mapped_column(String(16))  # cash|ecocash|onemoney|zipit|paynow|bank|card
    amount: Mapped[Decimal] = mapped_column(Money)
    currency: Mapped[str] = mapped_column(String(3))
    exchange_rate: Mapped[Decimal] = mapped_column(Rate)
    reference: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
