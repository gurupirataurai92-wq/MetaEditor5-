"""Kitchen stations and in-flight orders for LAKA LAKA CHICKEN.

A Station has a finite number of parallel slots (e.g. 3 fryers). Each slot
works one order-line at a time for its prep duration, then frees up.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional


@dataclass
class Order:
    """A customer's full order moving through the kitchen."""

    customer_id: int
    items: List[str]                 # menu item names still to be produced
    ready_items: int = 0             # count completed
    total_items: int = 0
    placed_minute: int = 0
    channel: str = "counter"

    def __post_init__(self):
        if self.total_items == 0:
            self.total_items = len(self.items)

    @property
    def complete(self) -> bool:
        return self.ready_items >= self.total_items


@dataclass
class _Slot:
    busy_until: int = -1
    order: Optional[Order] = None


class Station:
    """A kitchen station with `capacity` parallel cooking slots."""

    def __init__(self, name: str, capacity: int):
        self.name = name
        self.capacity = capacity
        self.slots: List[_Slot] = [_Slot() for _ in range(capacity)]
        self.busy_minutes = 0  # accumulated for utilization tracking

    def free_slot(self) -> Optional[_Slot]:
        for slot in self.slots:
            if slot.order is None:
                return slot
        return None

    def start(self, order: Order, prep_minutes: int, minute: int) -> bool:
        slot = self.free_slot()
        if slot is None:
            return False
        slot.order = order
        slot.busy_until = minute + prep_minutes
        return True

    def tick(self, minute: int) -> List[Order]:
        """Advance time; return orders whose current item just finished."""
        finished_for: List[Order] = []
        for slot in self.slots:
            if slot.order is not None:
                self.busy_minutes += 1
                if slot.busy_until <= minute:
                    order = slot.order
                    order.ready_items += 1
                    finished_for.append(order)
                    slot.order = None
                    slot.busy_until = -1
        return finished_for

    def utilization(self, elapsed_minutes: int) -> float:
        if elapsed_minutes <= 0 or self.capacity == 0:
            return 0.0
        return self.busy_minutes / (self.capacity * elapsed_minutes)
