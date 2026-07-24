"""Online storefront: public catalogue, guest ordering, and staff fulfilment
that flows into finance and per-branch inventory."""
from decimal import Decimal

from tests.conftest import API, make_product, make_user


def test_public_storefront_lists_active_products(client, biz):
    make_product(client, biz, name="Mazoe Orange", sell="3.75", stock=50)
    retired = make_product(client, biz, name="Old Stock", sell="1.00", stock=0)
    client.patch(f"{API}/products/{retired['id']}", headers=biz["headers"],
                 json={"is_active": False})

    store = client.get(f"{API}/public/{biz['tenant_id']}/store").json()
    names = [p["name"] for p in store["products"]]
    assert "Mazoe Orange" in names
    assert "Old Stock" not in names          # retired products are hidden
    assert store["business_name"]
    assert len(store["branches"]) >= 1


def test_guest_can_place_order_no_login(client, biz):
    product = make_product(client, biz, sell="11.50", stock=20)
    # Note: NO auth header — this is a customer at home.
    resp = client.post(f"{API}/public/{biz['tenant_id']}/orders", json={
        "customer_name": "Tariro Chlikwati",
        "customer_phone": "+263772000111",
        "fulfillment": "delivery",
        "customer_address": "12 Rowan Ave, Harare",
        "payment_method": "ecocash",
        "payment_reference": "MP55221",
        "items": [{"product_id": product["id"], "qty": 2}],
    })
    assert resp.status_code == 201, resp.text
    order = resp.json()
    assert order["number"].startswith("ORD-")
    assert order["status"] == "pending"
    assert Decimal(order["total"]) == Decimal("23.00")
    assert Decimal(order["tax_amount"]) == Decimal("3.00")  # VAT-inclusive
    # Customer can track it with the returned id.
    tracked = client.get(f"{API}/public/{biz['tenant_id']}/orders/{order['id']}")
    assert tracked.json()["status"] == "pending"


def test_order_price_is_server_side_not_client(client, biz):
    """Even if a tampered client sent a price, the server uses the catalogue."""
    product = make_product(client, biz, sell="10.00", stock=5)
    order = client.post(f"{API}/public/{biz['tenant_id']}/orders", json={
        "customer_name": "Hacker", "customer_phone": "+263700000000",
        "fulfillment": "pickup", "payment_method": "cash",
        "items": [{"product_id": product["id"], "qty": 1}],
    }).json()
    assert Decimal(order["total"]) == Decimal("10.00")  # not a client-sent value


def test_staff_see_and_fulfil_order_creating_a_sale(client, biz):
    product = make_product(client, biz, sell="10.00", cost="6.00", stock=10)
    order = client.post(f"{API}/public/{biz['tenant_id']}/orders", json={
        "customer_name": "Rudo", "customer_phone": "+263771234567",
        "fulfillment": "pickup", "payment_method": "cash",
        "items": [{"product_id": product["id"], "qty": 3}],
    }).json()

    # Staff see the pending order.
    orders = client.get(f"{API}/orders", headers=biz["headers"]).json()
    assert any(o["id"] == order["id"] for o in orders)

    # Confirm → fulfil. Fulfilment creates a real sale.
    client.patch(f"{API}/orders/{order['id']}", headers=biz["headers"],
                 json={"status": "confirmed"})
    fulfilled = client.patch(f"{API}/orders/{order['id']}", headers=biz["headers"],
                             json={"status": "fulfilled"}).json()
    assert fulfilled["status"] == "fulfilled"
    assert fulfilled["sale_id"]

    # The sale is in finance …
    pnl = client.get(f"{API}/reports/pnl", headers=biz["headers"]).json()
    assert Decimal(pnl["revenue_gross"]) == Decimal("30.00")
    # … and stock was decremented by fulfilment.
    levels = client.get(f"{API}/stock/levels", headers=biz["headers"]).json()
    on_hand = next(l["on_hand"] for l in levels if l["product_id"] == product["id"])
    assert on_hand == 7


def test_order_status_transitions_are_guarded(client, biz):
    product = make_product(client, biz, sell="5.00", stock=10)
    order = client.post(f"{API}/public/{biz['tenant_id']}/orders", json={
        "customer_name": "Xoli", "customer_phone": "+263700000000",
        "fulfillment": "pickup", "payment_method": "cash",
        "items": [{"product_id": product["id"], "qty": 1}],
    }).json()
    # Can't jump straight from pending to fulfilled.
    bad = client.patch(f"{API}/orders/{order['id']}", headers=biz["headers"],
                       json={"status": "fulfilled"})
    assert bad.status_code == 400


def test_cashier_can_fulfil_but_not_owner_reports(client, biz):
    cashier = make_user(client, biz, "cashier")
    product = make_product(client, biz, sell="5.00", stock=10)
    order = client.post(f"{API}/public/{biz['tenant_id']}/orders", json={
        "customer_name": "Xoli", "customer_phone": "+263700000000",
        "fulfillment": "pickup", "payment_method": "cash",
        "items": [{"product_id": product["id"], "qty": 1}],
    }).json()
    # A till operator handles orders …
    assert client.get(f"{API}/orders", headers=cashier["headers"]).status_code == 200
    ok = client.patch(f"{API}/orders/{order['id']}", headers=cashier["headers"],
                      json={"status": "confirmed"})
    assert ok.status_code == 200


def test_order_for_unknown_store_is_404(client):
    resp = client.get(f"{API}/public/not-a-real-tenant/store")
    assert resp.status_code == 404
