from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.contexts.finance.models import ExchangeRate


def latest_rate(db: Session, tenant_id: str, quote: str, base: str) -> Decimal | None:
    row = db.scalar(
        select(ExchangeRate)
        .where(
            ExchangeRate.tenant_id == tenant_id,
            ExchangeRate.quote == quote.upper(),
            ExchangeRate.base == base.upper(),
        )
        .order_by(ExchangeRate.captured_at.desc())
        .limit(1)
    )
    return row.rate if row else None


def resolve_rate(db: Session, tenant, currency: str,
                 explicit: Decimal | None) -> Decimal:
    """Rate to convert ``currency`` into the tenant's base currency.

    Prefers the explicitly captured transaction-time rate; falls back to the
    latest recorded rate; refuses to guess if neither exists.
    """
    if currency == tenant.base_currency:
        return Decimal("1")
    if explicit is not None:
        return explicit
    rate = latest_rate(db, tenant.id, currency, tenant.base_currency)
    if rate is None:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"No exchange rate available for {currency}->{tenant.base_currency}; "
            "supply exchange_rate or record one via /rates",
        )
    return rate
