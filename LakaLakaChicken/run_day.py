#!/usr/bin/env python3
"""Run one simulated day at LAKA LAKA CHICKEN and print the report.

Usage:
    python run_day.py [--seed N] [--cashiers N] [--rate PER_HOUR]
                      [--fryers N] [--grills N]
"""

from __future__ import annotations

import argparse

from laka_sim import ArrivalGenerator, Inventory, Restaurant, Simulation
from laka_sim.menu import build_menu


def main() -> None:
    p = argparse.ArgumentParser(description="LAKA LAKA CHICKEN day simulator")
    p.add_argument("--seed", type=int, default=None, help="RNG seed for reproducibility")
    p.add_argument("--cashiers", type=int, default=2, help="number of order-takers")
    p.add_argument("--rate", type=float, default=55.0, help="base arrivals per hour")
    p.add_argument("--fryers", type=int, default=3, help="fryer station slots")
    p.add_argument("--grills", type=int, default=2, help="grill station slots")
    p.add_argument("--drinks", type=int, default=2, help="drinks station slots")
    args = p.parse_args()

    menu = build_menu()
    restaurant = Restaurant(
        menu,
        Inventory(),
        num_cashiers=args.cashiers,
        station_capacity={"fryer": args.fryers, "grill": args.grills, "drinks": args.drinks},
    )
    arrivals = ArrivalGenerator(menu, base_rate_per_hour=args.rate)

    sim = Simulation(restaurant=restaurant, arrivals=arrivals, seed=args.seed)
    # keep the arrival generator's RNG in sync with the sim seed
    arrivals.rng = sim.rng

    report = sim.run()
    print(report.render())


if __name__ == "__main__":
    main()
