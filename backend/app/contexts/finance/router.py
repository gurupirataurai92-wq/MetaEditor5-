from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import audit
from app.core.audit import AuditLog
from app.core.db import get_db
from app.core.deps import AuthContext, get_auth, require
from app.core.money import money, rate as quantize_rate
from app.contexts.finance import reports
from app.contexts.finance.service import resolve_rate
from app.contexts.finance.models import ExchangeRate, Expense
from app.contexts.identity.models import Tenant

router = APIRouter(tags=["finance"])


class RateIn(BaseModel):
    quote: str = Field(min_length=3, max_length=3)  # e.g. ZWG
    rate: Decimal = Field(gt=0)                     # base units per 1 quote unit
    base: str | None = None                         # defaults to tenant base currency
    source: str = "manual"


class RateOut(BaseModel):
    base: str
    quote: str
    rate: Decimal
    source: str
    captured_at: datetime

    model_config = {"from_attributes": True}


class ExpenseIn(BaseModel):
    category: str
    amount: Decimal = Field(gt=0)
    currency: str = "USD"
    exchange_rate: Decimal | None = None
    description: str | None = None
    incurred_at: datetime | None = None


class ExpenseOut(BaseModel):
    id: str
    category: str
    amount: Decimal
    currency: str
    exchange_rate: Decimal
    description: str | None
    incurred_at: datetime

    model_config = {"from_attributes": True}


@router.post("/rates", response_model=RateOut, status_code=201,
             dependencies=[Depends(require("rates.create"))])
def record_rate(payload: RateIn, auth: AuthContext = Depends(get_auth),
                db: Session = Depends(get_db)):
    tenant = db.get(Tenant, auth.tenant_id)
    row = ExchangeRate(
        tenant_id=auth.tenant_id,
        base=(payload.base or tenant.base_currency).upper(),
        quote=payload.quote.upper(),
        rate=quantize_rate(payload.rate),
        source=payload.source,
    )
    db.add(row)
    db.flush()  # assign the id before it is audit-logged
    audit.record(db, tenant_id=auth.tenant_id, actor_id=auth.user_id, action="create",
                 entity="exchange_rate", entity_id=row.id,
                 data={"pair": f"{row.quote}->{row.base}", "rate": str(row.rate)})
    db.commit()
    return RateOut.model_validate(row)


@router.get("/rates", response_model=list[RateOut],
            dependencies=[Depends(require("rates.read"))])
def list_rates(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db),
               quote: str | None = None):
    q = select(ExchangeRate).where(ExchangeRate.tenant_id == auth.tenant_id)
    if quote:
        q = q.where(ExchangeRate.quote == quote.upper())
    rows = db.scalars(q.order_by(ExchangeRate.captured_at.desc()).limit(100)).all()
    return [RateOut.model_validate(r) for r in rows]


@router.post("/expenses", response_model=ExpenseOut, status_code=201,
             dependencies=[Depends(require("expenses.create"))])
def create_expense(payload: ExpenseIn, auth: AuthContext = Depends(get_auth),
                   db: Session = Depends(get_db)):
    tenant = db.get(Tenant, auth.tenant_id)
    exchange_rate = resolve_rate(db, tenant, payload.currency.upper(),
                                 payload.exchange_rate)
    expense = Expense(
        tenant_id=auth.tenant_id, category=payload.category,
        description=payload.description, amount=money(payload.amount),
        currency=payload.currency.upper(), exchange_rate=exchange_rate,
        created_by=auth.user_id,
        **({"incurred_at": payload.incurred_at} if payload.incurred_at else {}),
    )
    db.add(expense)
    db.flush()
    audit.record(db, tenant_id=auth.tenant_id, actor_id=auth.user_id, action="create",
                 entity="expense", entity_id=expense.id,
                 data={"category": expense.category, "amount": str(expense.amount)})
    db.commit()
    return ExpenseOut.model_validate(expense)


@router.get("/expenses", response_model=list[ExpenseOut],
            dependencies=[Depends(require("expenses.read"))])
def list_expenses(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    rows = db.scalars(
        select(Expense).where(Expense.tenant_id == auth.tenant_id)
        .order_by(Expense.incurred_at.desc()).limit(200)
    ).all()
    return [ExpenseOut.model_validate(e) for e in rows]


# ---------------------------------------------------------------- reports
@router.get("/reports/sales-summary", dependencies=[Depends(require("reports.read"))])
def sales_summary(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db),
                  date_from: datetime | None = None, date_to: datetime | None = None):
    return reports.sales_summary(db, auth.tenant_id, date_from, date_to)


@router.get("/reports/pnl", dependencies=[Depends(require("reports.read"))])
def pnl(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db),
        date_from: datetime | None = None, date_to: datetime | None = None):
    return reports.profit_and_loss(db, auth.tenant_id, date_from, date_to)


@router.get("/reports/cashflow", dependencies=[Depends(require("reports.read"))])
def cashflow(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db),
             date_from: datetime | None = None, date_to: datetime | None = None):
    return reports.cash_flow(db, auth.tenant_id, date_from, date_to)


# ------------------------------------------------------------------ audit
@router.get("/audit", dependencies=[Depends(require("audit.read"))])
def audit_trail(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db),
                limit: int = 100):
    rows = db.scalars(
        select(AuditLog).where(AuditLog.tenant_id == auth.tenant_id)
        .order_by(AuditLog.created_at.desc()).limit(min(limit, 500))
    ).all()
    return [
        {"id": r.id, "actor_id": r.actor_id, "action": r.action, "entity": r.entity,
         "entity_id": r.entity_id, "data": r.data, "created_at": r.created_at}
        for r in rows
    ]
