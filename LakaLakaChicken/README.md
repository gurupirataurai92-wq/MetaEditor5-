# 🍗 LAKA LAKA CHICKEN — Restaurant Sim System

A tick-based (minute-resolution) discrete simulation of running one
**LAKA LAKA CHICKEN** fast-food location for a business day. You configure
staffing, menu, and inventory; the sim generates customers, pushes them
through order-taking and the kitchen, and reports service quality and a full
profit-and-loss at close.

## Why it's interesting

The systems interact, so bottlenecks *move*. Understaff the kitchen and
customers walk out. Fix the kitchen and throughput jumps — but now inventory
drains faster and you start losing items to stockouts. There's no single
setting that wins; you tune against the day's demand curve.

```
Default (2 cashiers, 3 fryers)      Well-staffed (4 cashiers, 6 fryers)
  Service rate :  34.4%               Service rate :  82.7%
  Net profit   : -$863.63             Net profit   : +$911.45
  Bottleneck   : fryer @ 95%          Bottleneck   : inventory (182 stockouts)
```

## The model

| System | What it models |
|---|---|
| **Menu** (`menu.py`) | Buckets, Zinger burger, wings, fries, drinks, combos — each with price, ingredient cost, prep time, producing station, and recipe |
| **Inventory** (`inventory.py`) | Chicken, buns, potatoes, oil, drinks, spices — depletes per recipe, auto-reorders at a threshold with a delivery lead time, tracks stockouts |
| **Customers** (`customers.py`) | Arrive via a Poisson process shaped by a time-of-day demand curve (lunch + dinner rushes); each has a basket and a patience limit |
| **Stations** (`stations.py`) | Fryer / grill / drinks, each with finite parallel slots; queues form between order-taking and cooking |
| **Restaurant** (`restaurant.py`) | The floor: routes arrive → cashiers → stations → pickup, handles reneging and inventory consumption |
| **Finance** (`finance.py`) | Revenue − COGS − labor − overhead = net profit, plus per-item sales |
| **Simulation** (`simulation.py`) | Steps the clock across the service day + a wind-down, emits a `DayReport` |

### Pipeline

```
arrive ─▶ order-taking (cashiers) ─▶ kitchen stations ─▶ pickup ─▶ checkout
             │                            │
        (patience clock runs the whole time — exceed it and the customer walks)
```

## Running it

```bash
cd LakaLakaChicken

# one day with the default setup
python run_day.py --seed 42

# tune staffing and demand
python run_day.py --seed 42 --cashiers 4 --fryers 6 --grills 4 --rate 90

# tests
python -m unittest tests.test_simulation -v
```

CLI flags: `--seed`, `--cashiers`, `--rate` (arrivals/hour), `--fryers`,
`--grills`, `--drinks`.

## Layout

```
LakaLakaChicken/
├── README.md
├── run_day.py            # CLI entry point
├── laka_sim/
│   ├── menu.py           # menu items + recipes
│   ├── inventory.py      # stock, depletion, reordering
│   ├── customers.py      # arrivals + demand curve
│   ├── stations.py       # kitchen stations + orders
│   ├── restaurant.py     # floor orchestration
│   ├── finance.py        # P&L ledger
│   └── simulation.py     # day loop + report
└── tests/
    └── test_simulation.py
```

Pure standard library — no dependencies.

## Roadmap ideas

- **Drive-thru lane** as a separate queue with its own service dynamics
  (the `channel` field is already tracked on every customer/order).
- **Multi-day runs** with overnight inventory carry-over and spoilage.
- **Staff shifts** so labor scales with the demand curve instead of a flat day.
- **Promotions** (Laka Combo discount, happy-hour pricing) and their effect
  on basket mix and margin.
- **Optimizer sweep**: grid-search staffing to maximize profit at a given
  demand level.
- **Live dashboard**: render the minute-by-minute state as an HTML artifact.
