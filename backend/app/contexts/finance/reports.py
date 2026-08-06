"""Financial reports. All figures are converted to the tenant's base currency
using the exchange rate captured on each transaction — never today's rate —
so history stays economically meaningful under devaluation."""
from collections import defaultdict
from datetime import datetime
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.money import money, to_base
from app.contexts.finance.models import Expense
from app.contexts.inventory.models import Product
from app.contexts.sales.models import Payment, Sale, SaleLine


def _committed_sales(db: Session, tenant_id: str,
                     date_from: datetime | None, date_to: datetime | None,
                     shop_id: str | None = None) -> list[Sale]:
    q = select(Sale).where(Sale.tenant_id == tenant_id, Sale.status == "committed")
    if date_from:
        q = q.where(Sale.captured_at >= date_from)
    if date_to:
        q = q.where(Sale.captured_at <= date_to)
    if shop_id:
        q = q.where(Sale.shop_id == shop_id)
    return list(db.scalars(q).all())


def _scoped_expenses(db: Session, tenant_id: str,
                     date_from: datetime | None, date_to: datetime | None,
                     shop_id: str | None):
    q = select(Expense).where(Expense.tenant_id == tenant_id)
    if date_from:
        q = q.where(Expense.incurred_at >= date_from)
    if date_to:
        q = q.where(Expense.incurred_at <= date_to)
    if shop_id:
        q = q.where(Expense.shop_id == shop_id)
    return db.scalars(q).all()


def sales_summary(db: Session, tenant_id: str,
                  date_from: datetime | None = None,
                  date_to: datetime | None = None,
                  shop_id: str | None = None) -> dict:
    sales = _committed_sales(db, tenant_id, date_from, date_to, shop_id)
    by_day: dict[str, Decimal] = defaultdict(lambda: Decimal("0"))
    by_product: dict[str, dict] = {}
    revenue = Decimal("0")

    sale_ids = [s.id for s in sales]
    lines = (
        db.scalars(select(SaleLine).where(SaleLine.sale_id.in_(sale_ids))).all()
        if sale_ids else []
    )
    rate_by_sale = {s.id: s.exchange_rate for s in sales}

    for sale in sales:
        base_total = to_base(sale.total, sale.exchange_rate)
        revenue += base_total
        by_day[sale.captured_at.strftime("%Y-%m-%d")] += base_total
    for line in lines:
        entry = by_product.setdefault(
            line.product_id, {"name": line.product_name, "qty": 0,
                              "revenue": Decimal("0")})
        entry["qty"] += line.qty
        entry["revenue"] += to_base(line.line_total, rate_by_sale[line.sale_id])

    top = sorted(by_product.values(), key=lambda e: e["revenue"], reverse=True)
    return {
        "revenue": str(money(revenue)),
        "sales_count": len(sales),
        "by_day": [{"date": d, "revenue": str(money(v))} for d, v in sorted(by_day.items())],
        "top_products": [
            {"name": e["name"], "qty": e["qty"], "revenue": str(money(e["revenue"]))}
            for e in top[:10]
        ],
    }


def profit_and_loss(db: Session, tenant_id: str,
                    date_from: datetime | None = None,
                    date_to: datetime | None = None,
                    shop_id: str | None = None) -> dict:
    sales = _committed_sales(db, tenant_id, date_from, date_to, shop_id)
    sale_ids = [s.id for s in sales]
    rate_by_sale = {s.id: s.exchange_rate for s in sales}

    revenue = sum((to_base(s.total, s.exchange_rate) for s in sales), Decimal("0"))
    vat_collected = sum((to_base(s.tax_amount, s.exchange_rate) for s in sales),
                        Decimal("0"))

    lines = (
        db.scalars(select(SaleLine).where(SaleLine.sale_id.in_(sale_ids))).all()
        if sale_ids else []
    )
    product_costs = {
        p.id: p.cost_price
        for p in db.scalars(select(Product).where(Product.tenant_id == tenant_id)).all()
    }
    # Cost prices are held in base currency (see inventory model).
    cogs = sum(
        (Decimal(str(product_costs.get(l.product_id, 0))) * l.qty for l in lines),
        Decimal("0"),
    )

    expenses = _scoped_expenses(db, tenant_id, date_from, date_to, shop_id)
    expense_total = sum((to_base(e.amount, e.exchange_rate) for e in expenses),
                        Decimal("0"))

    gross_profit = revenue - vat_collected - cogs
    net_profit = gross_profit - expense_total
    return {
        "revenue_gross": str(money(revenue)),
        "vat_collected": str(money(vat_collected)),
        "revenue_net": str(money(revenue - vat_collected)),
        "cogs": str(money(cogs)),
        "gross_profit": str(money(gross_profit)),
        "expenses": str(money(expense_total)),
        "expenses_by_category": _expenses_by_category(expenses),
        "net_profit": str(money(net_profit)),
    }


def _expenses_by_category(expenses) -> list[dict]:
    grouped: dict[str, Decimal] = defaultdict(lambda: Decimal("0"))
    for e in expenses:
        grouped[e.category] += to_base(e.amount, e.exchange_rate)
    return [{"category": c, "amount": str(money(v))} for c, v in sorted(grouped.items())]


def cashier_performance(db: Session, tenant_id: str,
                        date_from: datetime | None = None,
                        date_to: datetime | None = None,
                        shop_id: str | None = None) -> list[dict]:
    """Per-cashier sales count, base-currency revenue and void count —
    the manager's till-monitoring view."""
    from app.contexts.identity.models import User

    q = select(Sale).where(Sale.tenant_id == tenant_id)
    if date_from:
        q = q.where(Sale.captured_at >= date_from)
    if date_to:
        q = q.where(Sale.captured_at <= date_to)
    if shop_id:
        q = q.where(Sale.shop_id == shop_id)
    sales = db.scalars(q).all()

    names = {
        u.id: u.full_name
        for u in db.scalars(select(User).where(User.tenant_id == tenant_id)).all()
    }
    per: dict[str, dict] = {}
    for sale in sales:
        entry = per.setdefault(sale.cashier_id, {
            "cashier_id": sale.cashier_id,
            "name": names.get(sale.cashier_id, "Unknown"),
            "sales_count": 0, "revenue": Decimal("0"), "voids": 0,
        })
        if sale.status == "void":
            entry["voids"] += 1
        else:
            entry["sales_count"] += 1
            entry["revenue"] += to_base(sale.total, sale.exchange_rate)

    rows = sorted(per.values(), key=lambda e: e["revenue"], reverse=True)
    return [
        {**row, "revenue": str(money(row["revenue"]))}
        for row in rows
    ]


def branch_breakdown(db: Session, tenant_id: str,
                     date_from: datetime | None = None,
                     date_to: datetime | None = None) -> list[dict]:
    """Revenue, net profit and sales count per branch (owner cross-branch view)."""
    from app.contexts.identity.models import Shop

    shops = db.scalars(select(Shop).where(Shop.tenant_id == tenant_id)).all()
    rows = []
    for shop in shops:
        pnl = profit_and_loss(db, tenant_id, date_from, date_to, shop.id)
        summary = sales_summary(db, tenant_id, date_from, date_to, shop.id)
        rows.append({
            "shop_id": shop.id,
            "name": shop.name,
            "address": shop.address,
            "revenue": pnl["revenue_gross"],
            "net_profit": pnl["net_profit"],
            "sales_count": summary["sales_count"],
        })
    return sorted(rows, key=lambda r: Decimal(r["revenue"]), reverse=True)


def cash_flow(db: Session, tenant_id: str,
              date_from: datetime | None = None,
              date_to: datetime | None = None,
              shop_id: str | None = None) -> dict:
    sales = _committed_sales(db, tenant_id, date_from, date_to, shop_id)
    sale_ids = {s.id for s in sales}
    payments = (
        db.scalars(select(Payment).where(Payment.tenant_id == tenant_id)).all()
        if sale_ids else []
    )
    inflows: dict[str, Decimal] = defaultdict(lambda: Decimal("0"))
    for p in payments:
        if p.sale_id in sale_ids:
            inflows[p.method] += to_base(p.amount, p.exchange_rate)

    expenses = _scoped_expenses(db, tenant_id, date_from, date_to, shop_id)

    inflow_total = sum(inflows.values(), Decimal("0"))
    outflow_total = sum((to_base(e.amount, e.exchange_rate) for e in expenses),
                        Decimal("0"))
    return {
        "inflows_by_method": [
            {"method": m, "amount": str(money(v))} for m, v in sorted(inflows.items())
        ],
        "inflows": str(money(inflow_total)),
        "outflows": str(money(outflow_total)),
        "net_cash_flow": str(money(inflow_total - outflow_total)),
    }
