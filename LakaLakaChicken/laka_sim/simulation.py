"""Top-level day simulation for LAKA LAKA CHICKEN.

Wires the arrival generator into the restaurant floor, steps the clock
minute-by-minute across the service day, then produces a DayReport.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from .customers import ArrivalGenerator
from .inventory import Inventory
from .menu import build_menu
from .restaurant import Restaurant


@dataclass
class DayReport:
    served: int
    lost: int
    dropped_items: int
    avg_wait: float
    revenue: float
    cogs: float
    labor_cost: float
    overhead: float
    restock_cost: float
    net_profit: float
    utilizations: Dict[str, float]
    top_sellers: List
    stockout_events: int
    end_inventory: Dict[str, int]

    @property
    def service_rate(self) -> float:
        total = self.served + self.lost
        return self.served / total if total else 0.0

    def render(self) -> str:
        lines = [
            "=" * 52,
            "   🍗  LAKA LAKA CHICKEN — END OF DAY REPORT  🍗",
            "=" * 52,
            f"  Customers served     : {self.served}",
            f"  Customers lost       : {self.lost}  (walked out)",
            f"  Service rate         : {self.service_rate * 100:5.1f}%",
            f"  Avg wait (served)    : {self.avg_wait:5.1f} min",
            f"  Items lost to stockout: {self.dropped_items}",
            "-" * 52,
            f"  Revenue              : ${self.revenue:10,.2f}",
            f"  COGS                 : ${self.cogs:10,.2f}",
            f"  Labor                : ${self.labor_cost:10,.2f}",
            f"  Overhead             : ${self.overhead:10,.2f}",
            f"  Restock spend        : ${self.restock_cost:10,.2f}",
            f"  NET PROFIT           : ${self.net_profit:10,.2f}",
            "-" * 52,
            "  Station utilization:",
        ]
        for name, util in self.utilizations.items():
            bar = "█" * int(util * 20)
            lines.append(f"    {name:<8}: {util * 100:5.1f}% {bar}")
        lines.append("  Top sellers:")
        for name, qty in self.top_sellers:
            lines.append(f"    {qty:>4} x {name}")
        lines.append("=" * 52)
        return "\n".join(lines)


class Simulation:
    def __init__(
        self,
        restaurant: Optional[Restaurant] = None,
        arrivals: Optional[ArrivalGenerator] = None,
        service_minutes: int = 12 * 60,
        wind_down_minutes: int = 30,
        seed: Optional[int] = None,
    ):
        self.rng = random.Random(seed)
        menu = build_menu()
        self.restaurant = restaurant or Restaurant(menu, Inventory())
        self.arrivals = arrivals or ArrivalGenerator(
            menu, base_rate_per_hour=55.0, rng=self.rng
        )
        self.service_minutes = service_minutes
        # extra minutes with no new arrivals so the kitchen can drain.
        self.wind_down_minutes = wind_down_minutes

    def run(self) -> DayReport:
        r = self.restaurant
        total_minutes = self.service_minutes + self.wind_down_minutes
        for minute in range(total_minutes):
            if minute < self.service_minutes:
                r.arrive(self.arrivals.arrivals_for_minute(minute))
            r.tick(minute)

        r.finalize(self.service_minutes)
        return DayReport(
            served=r.served,
            lost=r.lost_renege,
            dropped_items=r.dropped_items,
            avg_wait=r.avg_wait,
            revenue=r.ledger.revenue,
            cogs=r.ledger.cogs,
            labor_cost=r.ledger.labor_cost,
            overhead=r.ledger.overhead,
            restock_cost=r.ledger.restock_cost,
            net_profit=r.ledger.net_profit,
            utilizations=r.utilizations(self.service_minutes),
            top_sellers=r.ledger.top_sellers(),
            stockout_events=r.inventory.stockout_events,
            end_inventory=r.inventory.snapshot(),
        )
