"""The LAKA LAKA CHICKEN restaurant floor.

Orchestrates the full customer pipeline for one location:

    arrive -> order-taking (cashiers) -> kitchen stations -> pickup

Handles inventory consumption at cook-start, customer reneging when the
wait exceeds patience, and the finance ledger.
"""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from typing import Deque, Dict, List, Tuple

from .customers import Customer
from .finance import Ledger
from .inventory import Inventory
from .menu import MenuItem
from .stations import Order, Station


@dataclass
class _Task:
    """A single menu-item to be produced for an order."""
    order: Order
    item_name: str


class Restaurant:
    def __init__(
        self,
        menu: Dict[str, MenuItem],
        inventory: Inventory,
        num_cashiers: int = 2,
        station_capacity: Dict[str, int] | None = None,
        hourly_wage: float = 15.0,
        daily_overhead: float = 900.0,
    ):
        self.menu = menu
        self.inventory = inventory
        self.num_cashiers = num_cashiers
        self.hourly_wage = hourly_wage
        self.daily_overhead = daily_overhead

        caps = station_capacity or {"fryer": 3, "grill": 2, "drinks": 2}
        self.stations: Dict[str, Station] = {
            name: Station(name, cap) for name, cap in caps.items()
        }

        self.intake: Deque[Customer] = deque()
        self.pending: Dict[str, Deque[_Task]] = {n: deque() for n in self.stations}
        # customer id -> (Customer, Order)
        self.active: Dict[int, Tuple[Customer, Order]] = {}

        self.ledger = Ledger()
        self.served = 0
        self.lost_renege = 0
        self.total_wait = 0
        self.dropped_items = 0  # items refunded due to stockout

    # -- pipeline stages -------------------------------------------------

    def arrive(self, customers: List[Customer]) -> None:
        self.intake.extend(customers)

    def _take_orders(self, minute: int) -> None:
        """Cashiers pull from the intake line and open kitchen tickets."""
        for _ in range(self.num_cashiers):
            if not self.intake:
                break
            cust = self.intake.popleft()
            cust.order_taken_minute = minute
            order = Order(
                customer_id=cust.cid,
                items=list(cust.basket),
                total_items=len(cust.basket),
                placed_minute=minute,
                channel=cust.channel,
            )
            self.active[cust.cid] = (cust, order)
            for item_name in cust.basket:
                station = self.menu[item_name].station
                self.pending[station].append(_Task(order, item_name))

    def _dispatch(self, minute: int) -> None:
        """Fill free station slots from pending queues, consuming stock."""
        for name, station in self.stations.items():
            queue = self.pending[name]
            while queue and station.free_slot() is not None:
                task = queue.popleft()
                if task.order.customer_id not in self.active:
                    continue  # customer already reneged; skip the task
                item = self.menu[task.item_name]
                if not self.inventory.consume(item.recipe):
                    # Stockout: refund this line, shrink the order.
                    task.order.total_items -= 1
                    self.dropped_items += 1
                    continue
                station.start(task.order, item.prep_minutes, minute)

    def _cook(self, minute: int) -> None:
        for station in self.stations.values():
            station.tick(minute)  # advances ready_items on finished orders

    def _serve_and_renege(self, minute: int) -> None:
        done: List[int] = []
        for cid, (cust, order) in self.active.items():
            if order.total_items <= 0:
                # Whole order stocked out — treat as a lost sale.
                done.append(cid)
                self.lost_renege += 1
                continue
            if order.complete:
                self._checkout(cust, order, minute)
                done.append(cid)
            elif cust.wait_so_far(minute) > cust.patience:
                self.lost_renege += 1
                done.append(cid)
        for cid in done:
            self.active.pop(cid, None)

    def _checkout(self, cust: Customer, order: Order, minute: int) -> None:
        cust.served_minute = minute
        for item_name in cust.basket[: order.total_items]:
            item = self.menu[item_name]
            self.ledger.record_sale(item_name, item.price, item.cost)
        self.served += 1
        self.total_wait += cust.wait_so_far(minute)

    # -- main tick -------------------------------------------------------

    def tick(self, minute: int) -> None:
        self.inventory.tick(minute)
        self._take_orders(minute)
        self._dispatch(minute)
        self._cook(minute)
        self._serve_and_renege(minute)

    def finalize(self, elapsed_minutes: int) -> None:
        """Book labor + overhead + restock costs at day's end."""
        staff_count = self.num_cashiers + sum(s.capacity for s in self.stations.values())
        hours = elapsed_minutes / 60.0
        self.ledger.labor_cost = staff_count * self.hourly_wage * hours
        self.ledger.overhead = self.daily_overhead
        self.ledger.restock_cost = self.inventory.restock_spend

    # -- metrics ---------------------------------------------------------

    @property
    def avg_wait(self) -> float:
        return self.total_wait / self.served if self.served else 0.0

    def utilizations(self, elapsed_minutes: int) -> Dict[str, float]:
        return {n: s.utilization(elapsed_minutes) for n, s in self.stations.items()}
