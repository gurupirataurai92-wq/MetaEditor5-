from datetime import datetime
from decimal import Decimal

from sqlalchemy import DateTime, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, new_id, utcnow

Money = Numeric(18, 4)
Rate = Numeric(18, 6)


class ExchangeRate(Base):
    """Time-stamped rate history: ``rate`` = base units per 1 quote unit.

    Example: base=USD, quote=ZWG, rate=0.037 → 1 ZWG = 0.037 USD.
    Historical reporting always uses the rate captured on the transaction,
    never the latest row here (dissertation §4.5.2).
    """

    __tablename__ = "exchange_rates"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    base: Mapped[str] = mapped_column(String(3))
    quote: Mapped[str] = mapped_column(String(3))
    rate: Mapped[Decimal] = mapped_column(Rate)
    source: Mapped[str] = mapped_column(String(32), default="manual")  # manual|rbz|interbank
    captured_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Expense(Base):
    __tablename__ = "expenses"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    shop_id: Mapped[str | None] = mapped_column(String(36), index=True)  # branch
    category: Mapped[str] = mapped_column(String(64))  # rent|wages|transport|utilities|other
    description: Mapped[str | None] = mapped_column(String(255))
    amount: Mapped[Decimal] = mapped_column(Money)
    currency: Mapped[str] = mapped_column(String(3))
    exchange_rate: Mapped[Decimal] = mapped_column(Rate, default=Decimal("1"))
    incurred_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    created_by: Mapped[str | None] = mapped_column(String(36))
