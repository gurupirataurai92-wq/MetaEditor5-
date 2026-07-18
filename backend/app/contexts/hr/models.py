from datetime import date
from decimal import Decimal

from sqlalchemy import Date, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, new_id


class Employee(Base):
    """Employee master data. Payroll runs/payslips are a documented extension
    point (dissertation §1.8) built on top of this record."""

    __tablename__ = "employees"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    user_id: Mapped[str | None] = mapped_column(String(36))
    full_name: Mapped[str] = mapped_column(String(160))
    position: Mapped[str | None] = mapped_column(String(120))
    salary: Mapped[Decimal] = mapped_column(Numeric(18, 4), default=Decimal("0"))
    currency: Mapped[str] = mapped_column(String(3), default="USD")
    hired_at: Mapped[date | None] = mapped_column(Date)
