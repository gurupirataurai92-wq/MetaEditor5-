"""Per-branch finance/inventory, branch/staff deletion, payment editing and
per-till-operator history."""
import uuid
from decimal import Decimal

from tests.conftest import API, make_product, make_user


def _hire_cashier_at(client, biz, shop_id):
    """Owner hires a cashier assigned to a branch; returns their auth headers."""
    email = f"till-{uuid.uuid4().hex[:8]}@test.zw"
    emp = client.post(f"{API}/staff", headers=biz["headers"], json={
        "full_name": "Till Op", "role": "cashier", "shop_id": shop_id,
        "email": email, "password": "till-secret-123",
    })
    assert emp.status_code == 201, emp.text
    login = client.post(f"{API}/auth/login",
                        json={"email": email, "password": "till-secret-123"})
    return {"headers": {"Authorization": f"Bearer {login.json()['access_token']}"},
            "user_id": emp.json()["user_id"], "employee_id": emp.json()["id"]}


def test_owner_sees_finance_and_inventory_per_branch(client, biz):
    main = client.get(f"{API}/shops", headers=biz["headers"]).json()[0]
    branch = client.post(f"{API}/shops", headers=biz["headers"],
                         json={"name": "East Branch"}).json()
    product = make_product(client, biz, sell="10.00", cost="6.00", stock=100)

    # A cashier at each branch sells; sales are stamped with their branch.
    main_till = _hire_cashier_at(client, biz, main["id"])
    east_till = _hire_cashier_at(client, biz, branch["id"])
    client.post(f"{API}/sales", headers=main_till["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 3}]})
    client.post(f"{API}/sales", headers=east_till["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}]})

    # Per-branch P&L differs; the cross-branch breakdown sums to the whole.
    main_pnl = client.get(f"{API}/reports/pnl", headers=biz["headers"],
                          params={"shop_id": main["id"]}).json()
    east_pnl = client.get(f"{API}/reports/pnl", headers=biz["headers"],
                          params={"shop_id": branch["id"]}).json()
    assert Decimal(main_pnl["revenue_gross"]) == Decimal("30.00")
    assert Decimal(east_pnl["revenue_gross"]) == Decimal("10.00")

    breakdown = client.get(f"{API}/reports/branches", headers=biz["headers"]).json()
    by_name = {b["name"]: b for b in breakdown}
    assert Decimal(by_name["Main Shop"]["revenue"]) == Decimal("30.00")
    assert Decimal(by_name["East Branch"]["revenue"]) == Decimal("10.00")

    # Per-branch inventory: 3 units left the main branch, 1 the east branch.
    main_stock = client.get(f"{API}/stock/levels", headers=biz["headers"],
                            params={"shop_id": main["id"]}).json()
    east_stock = client.get(f"{API}/stock/levels", headers=biz["headers"],
                            params={"shop_id": branch["id"]}).json()
    main_qty = next(s["on_hand"] for s in main_stock if s["product_id"] == product["id"])
    east_qty = next(s["on_hand"] for s in east_stock if s["product_id"] == product["id"])
    # 100 units were received at the owner's main branch, then 3 sold there and
    # 1 at the east branch → stock is tracked independently per branch.
    assert main_qty == 97 and east_qty == -1


def test_per_till_operator_history(client, biz):
    product = make_product(client, biz, stock=50)
    till_a = _hire_cashier_at(client, biz, None)
    till_b = _hire_cashier_at(client, biz, None)
    client.post(f"{API}/sales", headers=till_a["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}]})
    client.post(f"{API}/sales", headers=till_a["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}]})
    client.post(f"{API}/sales", headers=till_b["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}]})

    # Owner filters history by operator.
    a_hist = client.get(f"{API}/sales", headers=biz["headers"],
                        params={"cashier_id": till_a["user_id"]}).json()
    assert len(a_hist) == 2 and all(s["cashier_id"] == till_a["user_id"] for s in a_hist)

    # A till operator only ever sees their own receipts, even unfiltered.
    own = client.get(f"{API}/sales", headers=till_b["headers"]).json()
    assert len(own) == 1 and own[0]["cashier_id"] == till_b["user_id"]


def test_owner_deletes_branch_unassigns_staff(client, biz):
    branch = client.post(f"{API}/shops", headers=biz["headers"],
                         json={"name": "Temp Branch"}).json()
    till = _hire_cashier_at(client, biz, branch["id"])
    resp = client.delete(f"{API}/shops/{branch['id']}", headers=biz["headers"])
    assert resp.status_code == 204
    assert branch["id"] not in [s["id"] for s in
                                client.get(f"{API}/shops", headers=biz["headers"]).json()]
    emp = next(e for e in client.get(f"{API}/employees", headers=biz["headers"]).json()
               if e["id"] == till["employee_id"])
    assert emp["shop_id"] is None  # reassigned


def test_cannot_delete_only_branch(client, biz):
    only = client.get(f"{API}/shops", headers=biz["headers"]).json()[0]
    resp = client.delete(f"{API}/shops/{only['id']}", headers=biz["headers"])
    assert resp.status_code == 400


def test_manager_cannot_delete_branch(client, biz):
    manager = make_user(client, biz, "manager")
    branch = client.post(f"{API}/shops", headers=biz["headers"],
                         json={"name": "B"}).json()
    resp = client.delete(f"{API}/shops/{branch['id']}", headers=manager["headers"])
    assert resp.status_code == 403


def test_manager_deletes_staff_and_login_revoked(client, biz):
    manager = make_user(client, biz, "manager")
    email = f"leaver-{uuid.uuid4().hex[:8]}@test.zw"
    emp = client.post(f"{API}/staff", headers=manager["headers"], json={
        "full_name": "Leaver", "role": "cashier",
        "email": email, "password": "leaver-secret-1"}).json()
    # They can log in now …
    assert client.post(f"{API}/auth/login",
                       json={"email": email, "password": "leaver-secret-1"}
                       ).status_code == 200
    assert client.delete(f"{API}/employees/{emp['id']}",
                         headers=manager["headers"]).status_code == 204
    # … but not after removal (login deactivated).
    assert client.post(f"{API}/auth/login",
                       json={"email": email, "password": "leaver-secret-1"}
                       ).status_code == 403


def test_owner_edits_recorded_payment(client, biz):
    product = make_product(client, biz, sell="10.00", stock=10)
    sale = client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}],
        "payments": [{"method": "cash", "amount": "10.00"}]}).json()
    payments = client.get(f"{API}/payments", headers=biz["headers"]).json()
    pay = next(p for p in payments if p["sale_id"] == sale["id"])
    assert pay["method"] == "cash"
    # Correct it: it was actually EcoCash.
    edited = client.patch(f"{API}/payments/{pay['id']}", headers=biz["headers"],
                          json={"method": "ecocash", "reference": "MP99887"})
    assert edited.status_code == 200
    assert edited.json()["method"] == "ecocash"
    assert edited.json()["reference"] == "MP99887"


def test_cashier_cannot_edit_payments(client, biz):
    cashier = make_user(client, biz, "cashier")
    product = make_product(client, biz, sell="10.00", stock=10)
    sale = client.post(f"{API}/sales", headers=cashier["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}]}).json()
    payments = client.get(f"{API}/payments", headers=biz["headers"]).json()
    pay = next(p for p in payments if p["sale_id"] == sale["id"])
    denied = client.patch(f"{API}/payments/{pay['id']}", headers=cashier["headers"],
                          json={"method": "bank"})
    assert denied.status_code == 403
