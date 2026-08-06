from decimal import Decimal

from tests.conftest import API, make_product


def test_pnl_revenue_cogs_expenses(client, biz):
    product = make_product(client, biz, sell="11.50", cost="5.00", stock=10)
    client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 2}]})  # 23.00 gross, 3.00 VAT
    client.post(f"{API}/expenses", headers=biz["headers"], json={
        "category": "rent", "amount": "4.00"})

    pnl = client.get(f"{API}/reports/pnl", headers=biz["headers"]).json()
    assert Decimal(pnl["revenue_gross"]) == Decimal("23.00")
    assert Decimal(pnl["vat_collected"]) == Decimal("3.00")
    assert Decimal(pnl["cogs"]) == Decimal("10.00")
    assert Decimal(pnl["gross_profit"]) == Decimal("10.00")   # 20 net - 10 cogs
    assert Decimal(pnl["expenses"]) == Decimal("4.00")
    assert Decimal(pnl["net_profit"]) == Decimal("6.00")


def test_voided_sales_excluded_from_reports(client, biz):
    product = make_product(client, biz, sell="10.00", stock=10)
    sale = client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}]}).json()
    client.post(f"{API}/sales/{sale['id']}/void", headers=biz["headers"])
    pnl = client.get(f"{API}/reports/pnl", headers=biz["headers"]).json()
    assert Decimal(pnl["revenue_gross"]) == Decimal("0.00")


def test_cashflow_groups_by_payment_method(client, biz):
    product = make_product(client, biz, sell="10.00", stock=10)
    client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}],
        "payments": [{"method": "ecocash", "amount": "10.00", "reference": "MP1"}]})
    cf = client.get(f"{API}/reports/cashflow", headers=biz["headers"]).json()
    methods = {i["method"]: i["amount"] for i in cf["inflows_by_method"]}
    assert Decimal(methods["ecocash"]) == Decimal("10.00")


def test_sales_summary_top_products(client, biz):
    fast = make_product(client, biz, name="Fast Mover", sell="2.00", stock=50)
    slow = make_product(client, biz, name="Slow Mover", sell="2.00", stock=50)
    for _ in range(3):
        client.post(f"{API}/sales", headers=biz["headers"], json={
            "lines": [{"product_id": fast["id"], "qty": 5}]})
    client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": slow["id"], "qty": 1}]})
    summary = client.get(f"{API}/reports/sales-summary", headers=biz["headers"]).json()
    assert summary["top_products"][0]["name"] == "Fast Mover"
    assert summary["sales_count"] == 4


def test_forecast_shape_and_bounds(client, biz):
    product = make_product(client, biz, stock=200)
    for _ in range(5):
        client.post(f"{API}/sales", headers=biz["headers"], json={
            "lines": [{"product_id": product["id"], "qty": 4}]})
    fc = client.get(f"{API}/analytics/forecast", headers=biz["headers"],
                    params={"days_ahead": 7}).json()
    assert len(fc["forecast"]) == 7
    for point in fc["forecast"]:
        assert 0 <= point["low"] <= point["value"] <= point["high"]
    assert len(fc["history"]) == 60


def test_reorder_suggestions_flag_low_stock(client, biz):
    product = make_product(client, biz, name="Kapenta", stock=10,
                           reorder_level=8)
    client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 4}]})  # on_hand 6 <= 8
    suggestions = client.get(f"{API}/analytics/reorder-suggestions",
                             headers=biz["headers"]).json()
    names = [s["name"] for s in suggestions]
    assert "Kapenta" in names
    entry = next(s for s in suggestions if s["name"] == "Kapenta")
    assert entry["suggested_order_qty"] >= 1


def test_deep_discount_anomaly_detected(client, biz):
    product = make_product(client, biz, name="Rice 5kg", sell="10.00", stock=10)
    client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1,
                   "unit_price": "5.00"}]})  # 50% below list
    anomalies = client.get(f"{API}/analytics/anomalies", headers=biz["headers"]).json()
    discounts = [a for a in anomalies if a["type"] == "deep_discount"]
    assert discounts and "Rice 5kg" in discounts[0]["product"]


def test_assistant_answers_are_grounded_in_tenant_data(client, biz):
    product = make_product(client, biz, sell="11.50", cost="5.00", stock=10)
    client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 2}]})
    resp = client.post(f"{API}/assistant/ask", headers=biz["headers"],
                       json={"question": "How is my profit this month?"})
    assert resp.status_code == 200
    body = resp.json()
    # The stated figure must equal the tenant's real P&L — grounded, not invented.
    pnl = client.get(f"{API}/reports/pnl", headers=biz["headers"]).json()
    assert pnl["net_profit"] in body["answer"]
    assert body["grounding"]["pnl_this_month"]["net_profit"] == pnl["net_profit"]


def test_assistant_isolation_between_tenants(client, biz, other_biz):
    product = make_product(client, biz, sell="100.00", stock=10)
    client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}]})
    resp = client.post(f"{API}/assistant/ask", headers=other_biz["headers"],
                       json={"question": "How is my profit this month?"})
    grounding = resp.json()["grounding"]
    assert Decimal(grounding["pnl_this_month"]["revenue_gross"]) == Decimal("0.00")


def test_cashier_performance_report(client, biz):
    from tests.conftest import make_user

    product = make_product(client, biz, sell="10.00", stock=30)
    cashier = make_user(client, biz, "cashier")
    # Owner sells twice; cashier sells once; owner voids one sale.
    client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}]})
    voided = client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}]}).json()
    client.post(f"{API}/sales/{voided['id']}/void", headers=biz["headers"])
    client.post(f"{API}/sales", headers=cashier["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 2}]})

    rows = client.get(f"{API}/reports/cashier-performance",
                      headers=biz["headers"]).json()
    by_name = {r["name"]: r for r in rows}
    owner_row = by_name["Test Owner"]
    cashier_row = by_name["Test cashier"]
    assert owner_row["sales_count"] == 1 and owner_row["voids"] == 1
    assert cashier_row["sales_count"] == 1
    assert Decimal(cashier_row["revenue"]) == Decimal("20.00")

    # The till operator cannot see the monitoring report.
    denied = client.get(f"{API}/reports/cashier-performance",
                        headers=cashier["headers"])
    assert denied.status_code == 403


def test_employee_crud(client, biz):
    resp = client.post(f"{API}/employees", headers=biz["headers"], json={
        "full_name": "Tino M.", "position": "Sales Assistant",
        "salary": "250.00", "currency": "USD"})
    assert resp.status_code == 201
    rows = client.get(f"{API}/employees", headers=biz["headers"]).json()
    assert rows[0]["full_name"] == "Tino M."
