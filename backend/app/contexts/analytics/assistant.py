"""AI business assistant — grounded answers over the tenant's own data.

Hexagonal port/adapter split (dissertation §4.7): the *retrieval* step
gathers real, tenant-isolated figures; the *generation* step turns them
into prose. The default adapter is a deterministic rule-based generator
(auditable, works offline, no API key). To use an LLM, implement
``AdvisorPort.generate`` with e.g. the Claude API and hand it the same
grounding payload — the retrieval boundary already enforces tenancy, so
the model can only ever see this tenant's numbers.
"""
from datetime import datetime, timedelta
from typing import Protocol

from sqlalchemy.orm import Session

from app.core.db import utcnow
from app.contexts.analytics import service as analytics
from app.contexts.finance import reports


class AdvisorPort(Protocol):
    def generate(self, question: str, grounding: dict) -> str: ...


def _month_start(now: datetime) -> datetime:
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


def retrieve_grounding(db: Session, tenant_id: str, question: str) -> dict:
    """Assemble the tenant-scoped facts relevant to the question."""
    now = utcnow()
    month_from = _month_start(now)
    prev_from = _month_start((month_from - timedelta(days=1)))
    grounding: dict = {
        "period": {"from": month_from.isoformat(), "to": now.isoformat()},
        "pnl_this_month": reports.profit_and_loss(db, tenant_id, month_from, now),
        "pnl_last_month": reports.profit_and_loss(db, tenant_id, prev_from, month_from),
    }
    q = question.lower()
    if any(w in q for w in ("stock", "reorder", "inventory", "order")):
        grounding["reorder"] = analytics.reorder_suggestions(db, tenant_id)
    if any(w in q for w in ("top", "best", "sell", "product")):
        grounding["sales_summary"] = reports.sales_summary(db, tenant_id, month_from, now)
    if any(w in q for w in ("cash", "money", "float")):
        grounding["cashflow"] = reports.cash_flow(db, tenant_id, month_from, now)
    if any(w in q for w in ("forecast", "next", "predict", "expect")):
        grounding["forecast"] = analytics.forecast(db, tenant_id, days_ahead=7)
    if any(w in q for w in ("fraud", "anomal", "suspicious", "theft")):
        grounding["anomalies"] = analytics.anomalies(db, tenant_id)
    return grounding


class RuleBasedAdvisor:
    """Deterministic, explainable advice from the grounding payload."""

    def generate(self, question: str, grounding: dict) -> str:
        q = question.lower()
        pnl = grounding["pnl_this_month"]
        prev = grounding["pnl_last_month"]
        parts: list[str] = []

        if any(w in q for w in ("profit", "loss", "margin", "why")):
            delta = float(pnl["net_profit"]) - float(prev["net_profit"])
            direction = "up" if delta >= 0 else "down"
            parts.append(
                f"This month your net profit is {pnl['net_profit']} "
                f"({direction} {abs(delta):.2f} vs last month's {prev['net_profit']}). "
                f"Net revenue is {pnl['revenue_net']}, cost of goods {pnl['cogs']}, "
                f"and expenses {pnl['expenses']}."
            )
            if float(pnl["expenses"]) > float(prev["expenses"]):
                parts.append("Expenses rose versus last month — review the largest "
                             "categories in the expense breakdown.")
        if "reorder" in grounding and grounding["reorder"]:
            names = ", ".join(s["name"] for s in grounding["reorder"][:5])
            parts.append(f"Restock soon: {names}. Suggested quantities are in the "
                         "reorder report.")
        if "sales_summary" in grounding and grounding["sales_summary"]["top_products"]:
            top = grounding["sales_summary"]["top_products"][0]
            parts.append(f"Your best seller this month is {top['name']} "
                         f"({top['qty']} sold, {top['revenue']} revenue).")
        if "cashflow" in grounding:
            cf = grounding["cashflow"]
            parts.append(f"Cash position this month: {cf['inflows']} in, "
                         f"{cf['outflows']} out, net {cf['net_cash_flow']}.")
        if "forecast" in grounding:
            total = sum(p["value"] for p in grounding["forecast"]["forecast"])
            parts.append(f"Projected revenue for the next 7 days: about {total:.2f} "
                         "(trend and weekday pattern based).")
        if "anomalies" in grounding:
            count = len(grounding["anomalies"])
            parts.append(
                f"{count} unusual pattern(s) flagged for review."
                if count else "No unusual transaction patterns detected."
            )
        if not parts:
            parts.append(
                f"Snapshot: net revenue {pnl['revenue_net']}, gross profit "
                f"{pnl['gross_profit']}, net profit {pnl['net_profit']} this month. "
                "Ask about profit, stock, top products, cash flow, forecasts or fraud."
            )
        return " ".join(parts)


_advisor: AdvisorPort = RuleBasedAdvisor()


def ask(db: Session, tenant_id: str, question: str) -> dict:
    grounding = retrieve_grounding(db, tenant_id, question)
    answer = _advisor.generate(question, grounding)
    return {
        "question": question,
        "answer": answer,
        "grounding": grounding,   # auditable evidence trail
        "model": type(_advisor).__name__,
    }
