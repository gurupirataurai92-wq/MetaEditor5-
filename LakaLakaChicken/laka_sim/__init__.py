"""LAKA LAKA CHICKEN — fast-food restaurant simulation engine.

A tick-based (minute-resolution) discrete simulation of running one
LAKA LAKA CHICKEN location for a business day. See README.md for the
design overview.
"""

from .menu import MenuItem, build_menu
from .inventory import Inventory, Ingredient
from .customers import Customer, ArrivalGenerator
from .stations import Station, Order
from .finance import Ledger
from .restaurant import Restaurant
from .simulation import Simulation, DayReport

__all__ = [
    "MenuItem",
    "build_menu",
    "Inventory",
    "Ingredient",
    "Customer",
    "ArrivalGenerator",
    "Station",
    "Order",
    "Ledger",
    "Restaurant",
    "Simulation",
    "DayReport",
]

__version__ = "0.1.0"
