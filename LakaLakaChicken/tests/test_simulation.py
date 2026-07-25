"""Smoke + sanity tests for the LAKA LAKA CHICKEN simulation."""

import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from laka_sim import ArrivalGenerator, Inventory, Restaurant, Simulation
from laka_sim.menu import build_menu
from laka_sim.inventory import Ingredient


class TestMenu(unittest.TestCase):
    def test_menu_margins_positive(self):
        for item in build_menu().values():
            self.assertGreater(item.margin, 0, f"{item.name} sells below cost")


class TestInventory(unittest.TestCase):
    def test_consume_and_stockout(self):
        inv = Inventory({"chicken": Ingredient("chicken", 3, 0, 0, 0.5, lead_minutes=999)})
        self.assertTrue(inv.consume({"chicken": 2}))
        self.assertFalse(inv.consume({"chicken": 2}))  # only 1 left
        self.assertEqual(inv.stockout_events, 1)

    def test_reorder_arrives(self):
        inv = Inventory({"buns": Ingredient("buns", 5, 10, 20, 0.2, lead_minutes=5)})
        inv.tick(0)   # below reorder point -> schedules restock
        self.assertEqual(inv.ingredients["buns"].units, 5)
        inv.tick(5)   # restock arrives
        self.assertEqual(inv.ingredients["buns"].units, 25)


class TestSimulation(unittest.TestCase):
    def test_day_runs_and_is_deterministic(self):
        r1 = Simulation(seed=42).run()
        r2 = Simulation(seed=42).run()
        self.assertEqual(r1.served, r2.served)
        self.assertEqual(round(r1.revenue, 2), round(r2.revenue, 2))

    def test_serves_customers_and_makes_revenue(self):
        report = Simulation(seed=7).run()
        self.assertGreater(report.served, 0)
        self.assertGreater(report.revenue, 0)
        self.assertGreaterEqual(report.service_rate, 0.0)
        self.assertLessEqual(report.service_rate, 1.0)

    def test_understaffing_lowers_service_rate(self):
        menu = build_menu()
        lean = Restaurant(
            menu, Inventory(), num_cashiers=1,
            station_capacity={"fryer": 1, "grill": 1, "drinks": 1},
        )
        lean_arr = ArrivalGenerator(menu, base_rate_per_hour=90.0)
        lean_sim = Simulation(restaurant=lean, arrivals=lean_arr, seed=1)
        lean_arr.rng = lean_sim.rng
        lean_report = lean_sim.run()

        big = Restaurant(
            menu, Inventory(), num_cashiers=4,
            station_capacity={"fryer": 5, "grill": 4, "drinks": 3},
        )
        big_arr = ArrivalGenerator(menu, base_rate_per_hour=90.0)
        big_sim = Simulation(restaurant=big, arrivals=big_arr, seed=1)
        big_arr.rng = big_sim.rng
        big_report = big_sim.run()

        self.assertLess(lean_report.service_rate, big_report.service_rate)


if __name__ == "__main__":
    unittest.main(verbosity=2)
