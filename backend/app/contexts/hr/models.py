from datetime import date
from decimal import Decimal

from sqlalchemy import Boolean, Date, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, new_id


class Employee(Base):
    """Employee master data with branch assignment and duty status —
    the manager's staffing view. Payroll runs/payslips are a documented
    extension point (dissertation §1.8) built on top of this record."""

    __tablename__ = "employees"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    user_id: Mapped[str | None] = mapped_column(String(36))
    shop_id: Mapped[str | None] = mapped_column(String(36))  # branch assignment
    full_name: Mapped[str] = mapped_column(String(160))
    position: Mapped[str | None] = mapped_column(String(120))
    on_duty: Mapped[bool] = mapped_column(Boolean, default=False)
    salary: Mapped[Decimal] = mapped_column(Numeric(18, 4), default=Decimal("0"))
    currency: Mapped[str] = mapped_column(String(3), default="USD")
    hired_at: Mapped[date | None] = mapped_column(Date)
