"""Menu definitions for LAKA LAKA CHICKEN.

Each menu item carries a price, a prep time (in sim minutes), the kitchen
station that produces it, and the recipe of ingredients it consumes.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List


@dataclass(frozen=True)
class MenuItem:
    """A single sellable product."""

    name: str
    price: float          # menu price charged to the customer
    cost: float           # ingredient cost (COGS) for margin tracking
    prep_minutes: int     # how long the producing station is busy
    station: str          # which station makes it: "fryer", "grill", "drinks"
    recipe: Dict[str, int] = field(default_factory=dict)  # ingredient -> units

    @property
    def margin(self) -> float:
        return self.price - self.cost


def build_menu() -> Dict[str, MenuItem]:
    """The signature LAKA LAKA CHICKEN menu."""
    items: List[MenuItem] = [
        MenuItem(
            name="Original Bucket (8pc)",
            price=18.99, cost=6.40, prep_minutes=6, station="fryer",
            recipe={"chicken": 8, "oil": 2, "spices": 2},
        ),
        MenuItem(
            name="Laka Zinger Burger",
            price=6.49, cost=2.10, prep_minutes=4, station="grill",
            recipe={"chicken": 1, "buns": 1, "spices": 1},
        ),
        MenuItem(
            name="Hot Wings (6pc)",
            price=5.99, cost=1.80, prep_minutes=5, station="fryer",
            recipe={"chicken": 3, "oil": 1, "spices": 2},
        ),
        MenuItem(
            name="Laka Fries",
            price=2.99, cost=0.70, prep_minutes=3, station="fryer",
            recipe={"potatoes": 2, "oil": 1},
        ),
        MenuItem(
            name="Soft Drink",
            price=1.99, cost=0.35, prep_minutes=1, station="drinks",
            recipe={"drinks": 1},
        ),
        MenuItem(
            name="Laka Combo (Zinger + Fries + Drink)",
            price=9.99, cost=3.15, prep_minutes=5, station="grill",
            recipe={"chicken": 1, "buns": 1, "potatoes": 2,
                    "oil": 1, "drinks": 1, "spices": 1},
        ),
    ]
    return {item.name: item for item in items}
