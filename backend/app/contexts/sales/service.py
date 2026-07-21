"""Sale creation — the single domain path used by both the POS API and the
offline sync engine.

Key invariants:
- **Idempotency:** the client-generated sale UUID is the primary key; a replay
  returns the existing sale instead of double-counting (dissertation §4.6).
- **Transaction-time currency capture:** amount, currency, base currency and
  exchange rate are persisted as at the moment of sale (§4.5.2).
- **VAT-inclusive pricing:** retail prices are gross; the VAT portion is
  extracted per line according to the product's tax class.
- **Oversell policy:** the online POS rejects insufficient stock, but sales
  arriving via sync are accepted and flagged — two offline tills may have
  legitimately sold the same last unit, and history must not be dropped.
"""
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import audit
from app.core.config import get_settings
from app.core.db import new_id, utcnow
from app.core.money import money, to_base, vat_portion
from app.contexts.finance.service import resolve_rate
from app.contexts.identity.models import Tenant
from app.contexts.inventory.models import StockMovement
from app.contexts.inventory.service import get_product, on_hand
from app.contexts.sales.models import Customer, Payment, Sale, SaleLine
from app.contexts.sales.schemas import SaleIn

PAYMENT_TOLERANCE = Decimal("0.05")  # base-currency units


def create_sale(db: Session, *, tenant_id: str, cashier_id: str, payload: SaleIn,
                allow_oversell: bool = False,
                default_shop_id: str | None = None) -> tuple[Sale, bool]:
    """Create a sale; returns (sale, created). Replays return created=False.

    The sale (and its stock movements) are stamped with the branch —
    ``payload.shop_id`` if given, else the operator's home branch — so every
    figure rolls up per-branch for owner reporting.
    """
    sale_id = payload.id or new_id()
    existing = db.get(Sale, sale_id)
    if existing is not None:
        if existing.tenant_id != tenant_id:
            raise HTTPException(status.HTTP_409_CONFLICT, "Sale id collision")
        return existing, False

    tenant = db.get(Tenant, tenant_id)
    settings = get_settings()
    currency = payload.currency.upper()
    exchange_rate = resolve_rate(db, tenant, currency, payload.exchange_rate)

    # Build lines, extract VAT, check stock.
    lines: list[SaleLine] = []
    total = Decimal("0")
    tax_total = Decimal("0")
    oversold: list[str] = []
    for line_in in payload.lines:
        product = get_product(db, tenant_id, line_in.product_id)
        if product is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND,
                                f"Product not found: {line_in.product_id}")
        unit_price = money(line_in.unit_price if line_in.unit_price is not None
                           else product.sell_price)
        line_total = money(unit_price * line_in.qty)
        tax = (vat_portion(line_total, settings.vat_rate)
               if product.tax_class == "standard" else Decimal("0.00"))

        available = on_hand(db, tenant_id, product.id)
        if available < line_in.qty:
            if not allow_oversell:
                raise HTTPException(
                    status.HTTP_409_CONFLICT,
                    f"Insufficient stock for {product.name}: have {available}, "
                    f"need {line_in.qty}",
                )
            oversold.append(product.name)

        lines.append(SaleLine(
            tenant_id=tenant_id, sale_id=sale_id, product_id=product.id,
            product_name=product.name, qty=line_in.qty, unit_price=unit_price,
            line_total=line_total, tax_amount=tax,
        ))
        total += line_total
        tax_total += tax

    total = money(total)
    tax_total = money(tax_total)

    # Payments: default to one cash payment covering the total.
    payments_in = payload.payments or []
    payments: list[Payment] = []
    paid_in_base = Decimal("0")
    for p in payments_in:
        p_currency = (p.currency or currency).upper()
        p_rate = resolve_rate(db, tenant, p_currency, p.exchange_rate)
        payments.append(Payment(
            tenant_id=tenant_id, sale_id=sale_id, method=p.method,
            amount=money(p.amount), currency=p_currency, exchange_rate=p_rate,
            reference=p.reference,
        ))
        paid_in_base += to_base(p.amount, p_rate)
    if not payments:
        payments.append(Payment(
            tenant_id=tenant_id, sale_id=sale_id, method="cash",
            amount=total, currency=currency, exchange_rate=exchange_rate,
        ))
        paid_in_base = to_base(total, exchange_rate)

    # Split/multi-currency payments must settle the sale within tolerance.
    total_in_base = to_base(total, exchange_rate)
    if abs(paid_in_base - total_in_base) > PAYMENT_TOLERANCE:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"Payments ({paid_in_base} {tenant.base_currency}) do not settle sale "
            f"total ({total_in_base} {tenant.base_currency})",
        )

    note = f"OVERSOLD: {', '.join(oversold)}" if oversold else None
    shop_id = payload.shop_id or default_shop_id
    sale = Sale(
        id=sale_id, tenant_id=tenant_id, shop_id=shop_id,
        customer_id=payload.customer_id, cashier_id=cashier_id,
        subtotal=money(total - tax_total), tax_amount=tax_total, total=total,
        currency=currency, base_currency=tenant.base_currency,
        exchange_rate=exchange_rate, rate_source=payload.rate_source,
        note=note, captured_at=payload.captured_at or utcnow(),
        lamport=payload.lamport,
    )
    db.add(sale)
    db.add_all(lines)
    db.add_all(payments)

    # Append the (immutable) stock ledger entries, stamped with the branch.
    for line in lines:
        db.add(StockMovement(
            tenant_id=tenant_id, shop_id=shop_id, product_id=line.product_id,
            movement_type="sale", qty=-line.qty, reference=sale_id,
            created_by=cashier_id,
        ))

    # Loyalty: one point per whole base-currency unit spent.
    if payload.customer_id:
        customer = db.get(Customer, payload.customer_id)
        if customer is not None and customer.tenant_id == tenant_id:
            customer.loyalty_points += int(total_in_base)

    audit.record(db, tenant_id=tenant_id, actor_id=cashier_id, action="create",
                 entity="sale", entity_id=sale_id,
                 data={"total": str(total), "currency": currency,
                       "exchange_rate": str(exchange_rate), "oversold": oversold})
    db.commit()
    return sale, True


def void_sale(db: Session, *, tenant_id: str, actor_id: str, sale_id: str) -> Sale:
    sale = db.get(Sale, sale_id)
    if sale is None or sale.tenant_id != tenant_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Sale not found")
    if sale.status == "void":
        return sale
    sale.status = "void"
    # Reverse stock by appending compensating movements (history is immutable).
    lines = db.scalars(select(SaleLine).where(SaleLine.sale_id == sale_id)).all()
    for line in lines:
        db.add(StockMovement(
            tenant_id=tenant_id, shop_id=sale.shop_id, product_id=line.product_id,
            movement_type="void", qty=line.qty, reference=sale_id,
            created_by=actor_id,
        ))
    audit.record(db, tenant_id=tenant_id, actor_id=actor_id, action="void",
                 entity="sale", entity_id=sale_id, data={"total": str(sale.total)})
    db.commit()
    return sale
