import uuid
from decimal import Decimal

from tests.conftest import API, make_product


def test_pos_sale_computes_inclusive_vat_and_decrements_stock(client, biz):
    product = make_product(client, biz, sell="11.50", stock=10)
    resp = client.post(f"{API}/sales", headers=biz["headers"], json={
        "currency": "USD",
        "lines": [{"product_id": product["id"], "qty": 2}],
    })
    assert resp.status_code == 201, resp.text
    sale = resp.json()
    assert Decimal(sale["total"]) == Decimal("23.00")
    # VAT-inclusive: 23.00 * 0.15/1.15 = 3.00
    assert Decimal(sale["tax_amount"]) == Decimal("3.00")
    assert Decimal(sale["subtotal"]) == Decimal("20.00")
    assert sale["payments"][0]["method"] == "cash"  # default settlement

    levels = client.get(f"{API}/stock/levels", headers=biz["headers"]).json()
    entry = next(l for l in levels if l["product_id"] == product["id"])
    assert entry["on_hand"] == 8


def test_zero_rated_product_has_no_vat(client, biz):
    product = make_product(client, biz, name="Bread", sell="1.00",
                           tax_class="zero", stock=5)
    sale = client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}]}).json()
    assert Decimal(sale["tax_amount"]) == Decimal("0.00")


def test_sale_idempotency_no_double_count(client, biz):
    product = make_product(client, biz, stock=10)
    sale_id = str(uuid.uuid4())
    payload = {"id": sale_id, "lines": [{"product_id": product["id"], "qty": 1}]}
    first = client.post(f"{API}/sales", headers=biz["headers"], json=payload)
    replay = client.post(f"{API}/sales", headers=biz["headers"], json=payload)
    assert first.status_code == 201
    assert replay.status_code == 200  # replay returns the existing sale
    assert replay.json()["id"] == sale_id

    levels = client.get(f"{API}/stock/levels", headers=biz["headers"]).json()
    entry = next(l for l in levels if l["product_id"] == product["id"])
    assert entry["on_hand"] == 9  # decremented exactly once


def test_online_pos_rejects_insufficient_stock(client, biz):
    product = make_product(client, biz, stock=1)
    resp = client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 5}]})
    assert resp.status_code == 409
    assert "Insufficient stock" in resp.json()["detail"]


def test_multicurrency_sale_captures_transaction_time_rate(client, biz):
    product = make_product(client, biz, name="Sugar 2kg", sell="98.00",
                           currency="ZWG", stock=20)
    # Record today's ZWG->USD rate, then sell in ZWG.
    client.post(f"{API}/rates", headers=biz["headers"],
                json={"quote": "ZWG", "rate": "0.0370", "source": "rbz"})
    sale = client.post(f"{API}/sales", headers=biz["headers"], json={
        "currency": "ZWG",
        "lines": [{"product_id": product["id"], "qty": 1}],
    })
    assert sale.status_code == 201, sale.text
    body = sale.json()
    assert body["currency"] == "ZWG"
    assert body["base_currency"] == "USD"
    assert Decimal(body["exchange_rate"]) == Decimal("0.037000")

    # A later devaluation must NOT rewrite history: the P&L uses the captured
    # rate (98 * 0.037 = 3.63), not the new one.
    client.post(f"{API}/rates", headers=biz["headers"],
                json={"quote": "ZWG", "rate": "0.0100", "source": "rbz"})
    pnl = client.get(f"{API}/reports/pnl", headers=biz["headers"]).json()
    assert Decimal(pnl["revenue_gross"]) == Decimal("3.63")


def test_split_currency_payment_settles_sale(client, biz):
    product = make_product(client, biz, name="Cooking Oil", sell="10.00", stock=5)
    client.post(f"{API}/rates", headers=biz["headers"],
                json={"quote": "ZWG", "rate": "0.0500"})
    # $6 cash + 80 ZWG EcoCash (= $4) settles a $10 sale.
    resp = client.post(f"{API}/sales", headers=biz["headers"], json={
        "currency": "USD",
        "lines": [{"product_id": product["id"], "qty": 1}],
        "payments": [
            {"method": "cash", "amount": "6.00"},
            {"method": "ecocash", "amount": "80.00", "currency": "ZWG",
             "reference": "MP12345"},
        ],
    })
    assert resp.status_code == 201, resp.text
    methods = {p["method"] for p in resp.json()["payments"]}
    assert methods == {"cash", "ecocash"}


def test_underpayment_rejected(client, biz):
    product = make_product(client, biz, sell="10.00", stock=5)
    resp = client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}],
        "payments": [{"method": "cash", "amount": "4.00"}],
    })
    assert resp.status_code == 400
    assert "do not settle" in resp.json()["detail"]


def test_void_reverses_stock_and_keeps_history(client, biz):
    product = make_product(client, biz, stock=10)
    sale = client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 4}]}).json()
    void = client.post(f"{API}/sales/{sale['id']}/void", headers=biz["headers"])
    assert void.status_code == 200
    assert void.json()["status"] == "void"
    levels = client.get(f"{API}/stock/levels", headers=biz["headers"]).json()
    entry = next(l for l in levels if l["product_id"] == product["id"])
    assert entry["on_hand"] == 10  # compensating movement restored stock


def test_loyalty_points_accrue_in_base_currency(client, biz):
    product = make_product(client, biz, sell="25.00", stock=5)
    customer = client.post(f"{API}/customers", headers=biz["headers"],
                           json={"name": "Amai Moyo"}).json()
    client.post(f"{API}/sales", headers=biz["headers"], json={
        "customer_id": customer["id"],
        "lines": [{"product_id": product["id"], "qty": 1}]})
    refreshed = client.get(f"{API}/customers/{customer['id']}",
                           headers=biz["headers"]).json()
    assert refreshed["loyalty_points"] == 25


def test_receipt_pdf_is_valid_pdf(client, biz):
    product = make_product(client, biz, stock=5)
    sale = client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}]}).json()
    resp = client.get(f"{API}/sales/{sale['id']}/receipt.pdf", headers=biz["headers"])
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "application/pdf"
    assert resp.content.startswith(b"%PDF-1.4")
    assert resp.content.rstrip().endswith(b"%%EOF")


def test_sales_are_audited(client, biz):
    product = make_product(client, biz, stock=5)
    client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}]})
    audit = client.get(f"{API}/audit", headers=biz["headers"]).json()
    assert any(e["entity"] == "sale" and e["action"] == "create" for e in audit)
