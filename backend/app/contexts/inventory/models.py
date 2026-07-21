from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import BigInteger, Boolean, Date, DateTime, Integer, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, new_id, utcnow

Money = Numeric(18, 4)


class Category(Base):
    __tablename__ = "categories"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    name: Mapped[str] = mapped_column(String(120))


class Product(Base):
    __tablename__ = "products"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    category_id: Mapped[str | None] = mapped_column(String(36))
    sku: Mapped[str] = mapped_column(String(64))
    name: Mapped[str] = mapped_column(String(200))
    barcode: Mapped[str | None] = mapped_column(String(20), index=True)
    # Cost prices are held in the tenant's base currency; sell price carries
    # its own currency and the applicable rate is captured on each sale.
    cost_price: Mapped[Decimal] = mapped_column(Money, default=Decimal("0"))
    sell_price: Mapped[Decimal] = mapped_column(Money, default=Decimal("0"))
    currency: Mapped[str] = mapped_column(String(3), default="USD")
    tax_class: Mapped[str] = mapped_column(String(16), default="standard")  # standard|zero|exempt
    reorder_level: Mapped[int] = mapped_column(Integer, default=0)
    batch_no: Mapped[str | None] = mapped_column(String(64))
    expiry_date: Mapped[date | None] = mapped_column(Date)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    # Lamport clock for last-writer-wins merge of master data during sync.
    lamport: Mapped[int] = mapped_column(BigInteger, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)


class Supplier(Base):
    __tablename__ = "suppliers"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    name: Mapped[str] = mapped_column(String(160))
    phone: Mapped[str | None] = mapped_column(String(32))
    email: Mapped[str | None] = mapped_column(String(255))
    address: Mapped[str | None] = mapped_column(String(255))


class StockMovement(Base):
    """Immutable, append-only stock ledger.

    Stock on hand is always a fold (SUM of qty) over this ledger — never a
    mutable counter — which is what makes offline replicas mergeable by
    simple union (dissertation §4.6).
    """

    __tablename__ = "stock_movements"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    shop_id: Mapped[str | None] = mapped_column(String(36), index=True)  # branch
    product_id: Mapped[str] = mapped_column(String(36), index=True)
    movement_type: Mapped[str] = mapped_column(String(16))  # purchase|sale|adjustment|return|void
    qty: Mapped[int] = mapped_column(Integer)  # signed delta
    unit_cost: Mapped[Decimal | None] = mapped_column(Money)
    reference: Mapped[str | None] = mapped_column(String(64))  # e.g. sale id, PO number
    note: Mapped[str | None] = mapped_column(String(255))
    created_by: Mapped[str | None] = mapped_column(String(36))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
