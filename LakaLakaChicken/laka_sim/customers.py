"""Customer arrivals and orders for LAKA LAKA CHICKEN.

Arrivals follow a time-of-day demand curve with lunch and dinner rushes.
Each customer carries a basket (list of menu item names) and a patience
limit — if their total wait exceeds it before pickup, they renege (leave).
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Dict, List

from .menu import MenuItem


@dataclass
class Customer:
    cid: int
    arrival_minute: int
    basket: List[str]                # menu item names ordered
    patience: int                    # max acceptable wait in minutes
    channel: str = "counter"         # "counter" or "drive_thru"
    order_taken_minute: int = -1
    served_minute: int = -1

    def wait_so_far(self, minute: int) -> int:
        return minute - self.arrival_minute

    def basket_value(self, menu: Dict[str, MenuItem]) -> float:
        return sum(menu[name].price for name in self.basket)


# Relative demand weight per hour of an 10:00–22:00 (12h) service day.
# Two humps: lunch (~12:00) and dinner (~18:00).
_HOURLY_WEIGHTS = [
    0.4,  # 10:00
    0.6,  # 11:00
    1.4,  # 12:00  <- lunch rush
    1.6,  # 13:00
    0.9,  # 14:00
    0.5,  # 15:00
    0.6,  # 16:00
    0.9,  # 17:00
    1.5,  # 18:00  <- dinner rush
    1.7,  # 19:00
    1.1,  # 20:00
    0.6,  # 21:00
]


class ArrivalGenerator:
    """Generates customers minute-by-minute using a Poisson-ish process."""

    def __init__(
        self,
        menu: Dict[str, MenuItem],
        base_rate_per_hour: float = 60.0,
        open_minute: int = 0,
        service_hours: int = 12,
        drive_thru_share: float = 0.45,
        rng: random.Random | None = None,
    ):
        self.menu = menu
        self.item_names = list(menu.keys())
        self.base_rate = base_rate_per_hour
        self.open_minute = open_minute
        self.service_hours = service_hours
        self.drive_thru_share = drive_thru_share
        self.rng = rng or random.Random()
        self._next_id = 0

    def _rate_at(self, minute: int) -> float:
        hour_index = (minute - self.open_minute) // 60
        if hour_index < 0 or hour_index >= len(_HOURLY_WEIGHTS):
            return 0.0
        weight = _HOURLY_WEIGHTS[hour_index]
        return self.base_rate * weight / 60.0  # per-minute expected arrivals

    def arrivals_for_minute(self, minute: int) -> List[Customer]:
        lam = self._rate_at(minute)
        count = _poisson(lam, self.rng)
        return [self._make_customer(minute) for _ in range(count)]

    def _make_customer(self, minute: int) -> Customer:
        self._next_id += 1
        basket_size = self.rng.choices([1, 2, 3, 4], weights=[45, 35, 15, 5])[0]
        basket = [self.rng.choice(self.item_names) for _ in range(basket_size)]
        patience = self.rng.randint(6, 18)
        channel = "drive_thru" if self.rng.random() < self.drive_thru_share else "counter"
        return Customer(
            cid=self._next_id,
            arrival_minute=minute,
            basket=basket,
            patience=patience,
            channel=channel,
        )


def _poisson(lam: float, rng: random.Random) -> int:
    """Knuth's algorithm for sampling a Poisson-distributed count."""
    if lam <= 0:
        return 0
    import math

    l = math.exp(-lam)
    k = 0
    p = 1.0
    while True:
        k += 1
        p *= rng.random()
        if p <= l:
            return k - 1
