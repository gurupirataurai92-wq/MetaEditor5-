"""Financial ledger for LAKA LAKA CHICKEN.

Tracks revenue, cost of goods sold, labor, and fixed overhead so the sim
can report a profit-and-loss summary at the end of the day.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict


@dataclass
class Ledger:
    revenue: float = 0.0
    cogs: float = 0.0
    labor_cost: float = 0.0
    overhead: float = 0.0
    restock_cost: float = 0.0
    item_sales: Dict[str, int] = field(default_factory=dict)

    def record_sale(self, item_name: str, price: float, cost: float) -> None:
        self.revenue += price
        self.cogs += cost
        self.item_sales[item_name] = self.item_sales.get(item_name, 0) + 1

    @property
    def gross_profit(self) -> float:
        return self.revenue - self.cogs

    @property
    def net_profit(self) -> float:
        return self.revenue - self.cogs - self.labor_cost - self.overhead

    def top_sellers(self, n: int = 3):
        return sorted(self.item_sales.items(), key=lambda kv: kv[1], reverse=True)[:n]
