#!/usr/bin/env python3
"""Seed a fully-populated demo business against a running SIMS AI API.

Creates "Glen View General Dealer" with six weeks of realistic sales
(weekday seasonality, month-end payday bumps), ZWG/USD rates, split-currency
payments, expenses, a customer with loyalty history, and a couple of
anomalies (a deep discount and a void) so every dashboard panel has data.

Usage:
    python3 scripts/seed_demo.py [http://localhost:8000]

Prints the login credentials when done. Safe to re-run: registration of an
existing email just reports the credentials again.
"""
import json
import random
import sys
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timedelta

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000") + "/api/v1"
EMAIL = "demo@simsai.co.zw"
PASSWORD = "demo-password-123"
MANAGER_EMAIL = "manager@simsai.co.zw"
MANAGER_PASSWORD = "manager-password-123"
TILL_EMAIL = "till@simsai.co.zw"
TILL_PASSWORD = "till-password-123"

_token: str | None = None


def call(path: str, data: dict | None = None, method: str | None = None) -> dict:
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(data).encode() if data is not None else None,
        headers={
            "Content-Type": "application/json",
            **({"Authorization": f"Bearer {_token}"} if _token else {}),
        },
        method=method or ("POST" if data is not None else "GET"),
    )
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def main() -> None:
    global _token
    random.seed(20)

    try:
        tokens = call("/auth/register-business", {
            "business_name": "Glen View General Dealer",
            "full_name": "Rudo Ncube",
            "email": EMAIL,
            "password": PASSWORD,
        })
        print("Registered new demo business.")
    except urllib.error.HTTPError as e:
        if e.code != 409:
            raise
        tokens = call("/auth/login", {"email": EMAIL, "password": PASSWORD})
        print("Demo business already exists — logged in; skipping seeding.")
        print(f"\n  URL:      {BASE.removesuffix('/api/v1')}\n"
              f"  Email:    {EMAIL}\n  Password: {PASSWORD}")
        return
    _token = tokens["access_token"]

    # Exchange rate history (ZWG gently devaluing against USD).
    for days_ago, rate in [(42, "0.0400"), (28, "0.0385"), (14, "0.0372"), (2, "0.0361")]:
        call("/rates", {"quote": "ZWG", "rate": rate, "source": "rbz"})

    catalogue = [
        ("Mazoe Orange 2L", "3.75", "2.10"), ("Sugar 2kg", "2.80", "1.80"),
        ("Cooking Oil 750ml", "2.30", "1.45"), ("Bread", "1.10", "0.70"),
        ("Maize Meal 10kg", "7.50", "5.20"), ("Soap Bar", "0.90", "0.45"),
        ("Rice 5kg", "6.20", "4.10"), ("Kapenta 500g", "4.40", "2.70"),
    ]
    products = []
    for name, sell, cost in catalogue:
        product = call("/products", {
            "name": name, "sell_price": sell, "cost_price": cost,
            "reorder_level": 25,
        })
        call("/stock/movements", {
            "product_id": product["id"], "movement_type": "purchase",
            "qty": 500, "unit_cost": cost, "reference": "PO-0001",
        })
        products.append(product)

    customer = call("/customers", {"name": "Amai Moyo", "phone": "+263771234567"})

    weekday_weight = [3, 3, 3, 4, 6, 8, 2]  # Sat busiest, Sun quiet
    now = datetime.utcnow()
    sales_created = 0
    for days_ago in range(42, 0, -1):
        day = now - timedelta(days=days_ago)
        n_sales = weekday_weight[day.weekday()] + (2 if day.day >= 25 else 0)
        for _ in range(random.randint(max(1, n_sales - 2), n_sales + 2)):
            picks = random.sample(products, k=random.randint(1, 3))
            lines = [{"product_id": p["id"], "qty": random.randint(1, 4)} for p in picks]
            sale: dict = {
                "id": str(uuid.uuid4()), "currency": "USD", "lines": lines,
                "captured_at": day.replace(hour=random.randint(7, 18),
                                           minute=random.randint(0, 59)).isoformat(),
            }
            if random.random() < 0.25:
                sale["customer_id"] = customer["id"]
            if random.random() < 0.30:  # mobile-money settlement
                sale["payments"] = None  # priced below after totals are known
            call("/sales", sale)
            sales_created += 1

    # A few non-cash payment sales (EcoCash / ZIPIT) for the cash-flow panel.
    for method in ("ecocash", "ecocash", "zipit", "paynow"):
        p = random.choice(products)
        call("/sales", {
            "id": str(uuid.uuid4()), "currency": "USD",
            "lines": [{"product_id": p["id"], "qty": 2}],
            "payments": [{"method": method,
                          "amount": f"{float(p['sell_price']) * 2:.2f}",
                          "reference": f"MP{random.randint(10000, 99999)}"}],
        })
        sales_created += 1

    # Anomalies for the alerts panel: a deep discount and a voided sale.
    rice = next(p for p in products if p["name"].startswith("Rice"))
    call("/sales", {
        "id": str(uuid.uuid4()), "currency": "USD",
        "lines": [{"product_id": rice["id"], "qty": 1, "unit_price": "3.00"}],
    })
    voided = call("/sales", {
        "id": str(uuid.uuid4()), "currency": "USD",
        "lines": [{"product_id": rice["id"], "qty": 1}],
    })
    call(f"/sales/{voided['id']}/void", {})

    for category, amount in [("rent", "80.00"), ("transport", "25.00"),
                             ("utilities", "32.50"), ("wages", "140.00")]:
        call("/expenses", {"category": category, "amount": amount})

    # Owner opens a second branch and appoints the manager.
    shops = call("/shops")
    main_shop = shops[0]
    branch = call("/shops", {"name": "Mbare Branch",
                             "address": "Stall 14, Mbare Musika, Harare"})
    call("/users", {"email": MANAGER_EMAIL, "password": MANAGER_PASSWORD,
                    "full_name": "Nyasha Chikafu", "role": "manager"})
    owner_token = _token

    # The manager hires the team; each employee's password is their own.
    _token = call("/auth/login", {"email": MANAGER_EMAIL,
                                  "password": MANAGER_PASSWORD})["access_token"]
    till_emp = call("/staff", {
        "full_name": "Tatenda (Till 1)", "position": "Till Operator",
        "shop_id": main_shop["id"], "role": "cashier",
        "email": TILL_EMAIL, "password": TILL_PASSWORD, "salary": "180.00",
    })
    call(f"/employees/{till_emp['id']}", {"on_duty": True}, method="PATCH")
    rumbi = call("/staff", {
        "full_name": "Rumbi K.", "position": "Storekeeper",
        "shop_id": branch["id"], "role": "storekeeper",
        "email": f"rumbi-{uuid.uuid4().hex[:6]}@simsai.co.zw",
        "password": "rumbi-own-secret-1", "salary": "160.00",
    })
    assert rumbi["on_duty"] is False  # off duty until she clocks in

    # The till operator serves customers *today* → Live Monitor has activity.
    _token = call("/auth/login",
                  {"email": TILL_EMAIL, "password": TILL_PASSWORD})["access_token"]
    for _ in range(5):
        p = random.choice(products)
        call("/sales", {
            "id": str(uuid.uuid4()), "currency": "USD",
            "lines": [{"product_id": p["id"], "qty": random.randint(1, 3)}],
        })
        sales_created += 1
    _token = owner_token

    print(f"Seeded {sales_created + 2} sales, {len(catalogue)} products, "
          "2 branches, a manager, 2 staff, expenses, rates and anomalies.")
    print(f"\n  URL:            {BASE.removesuffix('/api/v1')}\n"
          f"  Owner login:    {EMAIL} / {PASSWORD}\n"
          f"  Manager login:  {MANAGER_EMAIL} / {MANAGER_PASSWORD}\n"
          f"  Till login:     {TILL_EMAIL} / {TILL_PASSWORD}")


if __name__ == "__main__":
    main()
