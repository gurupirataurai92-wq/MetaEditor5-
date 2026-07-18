"""Lightweight, dependency-free analytics engine.

Deliberately statistical rather than deep-learning (dissertation §2.5, H2):
informal-sector series are short, sparse and noisy, where trend + weekday
seasonality with an empirical residual band is a strong, explainable
baseline. The heavier Prophet/XGBoost pipelines live in ``ml/`` and serve
through the same response shapes, so swapping them in is a deployment
choice, not an API change.
"""
import math
import statistics
from datetime import date, datetime, time, timedelta
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.db import utcnow
from app.core.money import to_base
from app.contexts.inventory.models import Product
from app.contexts.inventory.service import on_hand
from app.contexts.sales.models import Sale, SaleLine


def daily_series(db: Session, tenant_id: str, days: int,
                 product_id: str | None = None) -> list[dict]:
    """Gap-filled daily (date, revenue_base, qty) series for the last N days."""
    since = datetime.combine(utcnow().date() - timedelta(days=days - 1), time.min)
    sales = db.scalars(
        select(Sale).where(Sale.tenant_id == tenant_id, Sale.status == "committed",
                           Sale.captured_at >= since)
    ).all()
    rate_by_sale = {s.id: s.exchange_rate for s in sales}
    day_revenue: dict[date, Decimal] = {}
    day_qty: dict[date, int] = {}

    if product_id is None:
        for s in sales:
            d = s.captured_at.date()
            day_revenue[d] = day_revenue.get(d, Decimal("0")) + to_base(s.total, s.exchange_rate)
    lines = (
        db.scalars(select(SaleLine).where(
            SaleLine.sale_id.in_([s.id for s in sales]))).all()
        if sales else []
    )
    captured_by_sale = {s.id: s.captured_at.date() for s in sales}
    for line in lines:
        if product_id is not None and line.product_id != product_id:
            continue
        d = captured_by_sale[line.sale_id]
        day_qty[d] = day_qty.get(d, 0) + line.qty
        if product_id is not None:
            day_revenue[d] = day_revenue.get(d, Decimal("0")) + to_base(
                line.line_total, rate_by_sale[line.sale_id])

    series = []
    for i in range(days):
        d = since.date() + timedelta(days=i)
        series.append({
            "date": d.isoformat(),
            "revenue": float(day_revenue.get(d, Decimal("0"))),
            "qty": day_qty.get(d, 0),
        })
    return series


def _fit_trend(values: list[float]) -> tuple[float, float, float]:
    """Least-squares line fit; returns (intercept, slope, residual_std)."""
    n = len(values)
    xs = list(range(n))
    mean_x = sum(xs) / n
    mean_y = sum(values) / n
    denom = sum((x - mean_x) ** 2 for x in xs) or 1.0
    slope = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, values)) / denom
    intercept = mean_y - slope * mean_x
    residuals = [y - (intercept + slope * x) for x, y in zip(xs, values)]
    resid_std = statistics.pstdev(residuals) if n > 1 else 0.0
    return intercept, slope, resid_std


def forecast(db: Session, tenant_id: str, *, days_ahead: int = 14,
             window: int = 60, product_id: str | None = None) -> dict:
    history = daily_series(db, tenant_id, window, product_id)
    metric = "qty" if product_id else "revenue"
    values = [float(p[metric]) for p in history]
    n = len(values)

    intercept, slope, resid_std = _fit_trend(values)

    # Multiplicative weekday factors (guarding against div-by-zero).
    overall_mean = (sum(values) / n) if n else 0.0
    weekday_totals: dict[int, list[float]] = {i: [] for i in range(7)}
    start = date.fromisoformat(history[0]["date"]) if history else utcnow().date()
    for i, v in enumerate(values):
        weekday_totals[(start + timedelta(days=i)).weekday()].append(v)
    factors = {
        wd: (statistics.mean(vs) / overall_mean if vs and overall_mean > 0 else 1.0)
        for wd, vs in weekday_totals.items()
    }

    points = []
    band = 1.96 * resid_std
    for i in range(1, days_ahead + 1):
        d = start + timedelta(days=n - 1 + i)
        base_value = intercept + slope * (n - 1 + i)
        value = max(0.0, base_value * factors[d.weekday()])
        points.append({
            "date": d.isoformat(),
            "value": round(value, 2),
            "low": round(max(0.0, value - band), 2),
            "high": round(value + band, 2),
        })
    return {
        "metric": metric,
        "product_id": product_id,
        "model": "trend+weekday-v1",
        "history": history,
        "forecast": points,
    }


def reorder_suggestions(db: Session, tenant_id: str, *, lead_time_days: int = 7,
                        window: int = 30, service_z: float = 1.65) -> list[dict]:
    """Classical reorder point: demand over lead time + safety stock."""
    products = db.scalars(
        select(Product).where(Product.tenant_id == tenant_id, Product.is_active)
    ).all()
    suggestions = []
    for product in products:
        series = daily_series(db, tenant_id, window, product.id)
        daily_qty = [p["qty"] for p in series]
        mean_demand = statistics.mean(daily_qty) if daily_qty else 0.0
        std_demand = statistics.pstdev(daily_qty) if len(daily_qty) > 1 else 0.0
        safety = service_z * std_demand * math.sqrt(lead_time_days)
        reorder_point = mean_demand * lead_time_days + safety
        stock = on_hand(db, tenant_id, product.id)
        threshold = max(reorder_point, float(product.reorder_level))
        if stock <= threshold and (mean_demand > 0 or stock <= product.reorder_level):
            target = mean_demand * lead_time_days * 2 + safety
            suggestions.append({
                "product_id": product.id,
                "name": product.name,
                "on_hand": stock,
                "avg_daily_demand": round(mean_demand, 2),
                "reorder_point": round(reorder_point, 1),
                "suggested_order_qty": max(1, math.ceil(target - stock)),
            })
    return sorted(suggestions, key=lambda s: s["on_hand"])


def anomalies(db: Session, tenant_id: str, *, window: int = 30,
              z_threshold: float = 2.5, discount_threshold: float = 0.30) -> list[dict]:
    findings: list[dict] = []

    # 1. Daily revenue outliers (z-score).
    series = daily_series(db, tenant_id, window)
    revenues = [p["revenue"] for p in series]
    if len(revenues) >= 7:
        mean = statistics.mean(revenues)
        std = statistics.pstdev(revenues)
        if std > 0:
            for p in series:
                z = (p["revenue"] - mean) / std
                if abs(z) >= z_threshold and p["revenue"] > 0:
                    findings.append({
                        "type": "revenue_outlier", "severity": "medium",
                        "date": p["date"], "z_score": round(z, 2),
                        "detail": f"Daily revenue {p['revenue']:.2f} deviates "
                                  f"{z:+.1f} sigma from the {window}-day mean",
                    })

    # 2. Deep-discount lines (possible sweethearting / mis-keying).
    since = utcnow() - timedelta(days=window)
    sales = db.scalars(
        select(Sale).where(Sale.tenant_id == tenant_id,
                           Sale.captured_at >= since)).all()
    sale_by_id = {s.id: s for s in sales}
    lines = (
        db.scalars(select(SaleLine).where(
            SaleLine.sale_id.in_(list(sale_by_id)))).all()
        if sales else []
    )
    list_prices = {
        p.id: p.sell_price
        for p in db.scalars(select(Product).where(Product.tenant_id == tenant_id)).all()
    }
    for line in lines:
        list_price = list_prices.get(line.product_id)
        if not list_price or list_price <= 0:
            continue
        discount = 1 - float(line.unit_price) / float(list_price)
        if discount >= discount_threshold:
            findings.append({
                "type": "deep_discount", "severity": "high",
                "sale_id": line.sale_id,
                "product": line.product_name,
                "detail": f"Sold at {discount:.0%} below list price "
                          f"({line.unit_price} vs {list_price})",
                "cashier_id": sale_by_id[line.sale_id].cashier_id,
            })

    # 3. Void frequency per cashier.
    void_counts: dict[str, int] = {}
    for s in sales:
        if s.status == "void":
            void_counts[s.cashier_id] = void_counts.get(s.cashier_id, 0) + 1
    for cashier_id, count in void_counts.items():
        if count >= 3:
            findings.append({
                "type": "void_frequency", "severity": "high",
                "cashier_id": cashier_id,
                "detail": f"{count} voided sales in the last {window} days",
            })

    # 4. Oversold flags recorded during offline sync.
    for s in sales:
        if s.note and s.note.startswith("OVERSOLD"):
            findings.append({
                "type": "oversell", "severity": "low", "sale_id": s.id,
                "detail": s.note,
            })
    return findings
