"""Inventory tracking for LAKA LAKA CHICKEN.

Ingredients deplete as menu items are produced. When stock drops below a
reorder point a restock is scheduled; restocks arrive after a lead time.
Any stock beyond shelf life at day's end counts as waste.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple


@dataclass
class Ingredient:
    name: str
    units: int              # current stock on hand
    reorder_point: int      # trigger a restock at or below this level
    reorder_qty: int        # how many units a restock delivers
    unit_cost: float        # purchase cost per unit
    lead_minutes: int = 30  # delay before a restock arrives


class Inventory:
    """Holds all ingredients and manages depletion + reordering."""

    def __init__(self, ingredients: Optional[Dict[str, Ingredient]] = None):
        self.ingredients: Dict[str, Ingredient] = ingredients or _default_stock()
        # pending restocks as (arrival_minute, ingredient_name, qty, cost)
        self._pending: List[Tuple[int, str, int, float]] = []
        self.restock_spend: float = 0.0
        self.stockout_events: int = 0

    def can_make(self, recipe: Dict[str, int]) -> bool:
        return all(
            self.ingredients[name].units >= qty
            for name, qty in recipe.items()
            if name in self.ingredients
        )

    def consume(self, recipe: Dict[str, int]) -> bool:
        """Deplete ingredients for a recipe. Returns False on a stockout."""
        if not self.can_make(recipe):
            self.stockout_events += 1
            return False
        for name, qty in recipe.items():
            if name in self.ingredients:
                self.ingredients[name].units -= qty
        return True

    def tick(self, minute: int) -> None:
        """Deliver any arrived restocks and place new orders as needed."""
        # Deliver arrivals due at or before this minute.
        remaining = []
        for arrival, name, qty, cost in self._pending:
            if arrival <= minute:
                self.ingredients[name].units += qty
                self.restock_spend += cost
            else:
                remaining.append((arrival, name, qty, cost))
        self._pending = remaining

        # Place new orders for anything at/under its reorder point and not
        # already inbound.
        inbound = {name for _, name, _, _ in self._pending}
        for name, ing in self.ingredients.items():
            if ing.units <= ing.reorder_point and name not in inbound:
                cost = ing.reorder_qty * ing.unit_cost
                self._pending.append(
                    (minute + ing.lead_minutes, name, ing.reorder_qty, cost)
                )

    def snapshot(self) -> Dict[str, int]:
        return {name: ing.units for name, ing in self.ingredients.items()}


def _default_stock() -> Dict[str, Ingredient]:
    defs = [
        Ingredient("chicken", units=400, reorder_point=80, reorder_qty=300, unit_cost=0.55),
        Ingredient("buns", units=200, reorder_point=40, reorder_qty=150, unit_cost=0.20),
        Ingredient("potatoes", units=300, reorder_point=60, reorder_qty=200, unit_cost=0.10),
        Ingredient("oil", units=120, reorder_point=30, reorder_qty=100, unit_cost=0.25),
        Ingredient("drinks", units=250, reorder_point=50, reorder_qty=200, unit_cost=0.15),
        Ingredient("spices", units=300, reorder_point=60, reorder_qty=200, unit_cost=0.08),
    ]
    return {ing.name: ing for ing in defs}
