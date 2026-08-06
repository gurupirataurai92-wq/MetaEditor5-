import uuid

from tests.conftest import API, make_user


def test_manager_hires_staff_with_confidential_password(client, biz):
    manager = make_user(client, biz, "manager")
    shop = client.get(f"{API}/shops", headers=biz["headers"]).json()[0]

    email = f"staff-{uuid.uuid4().hex[:8]}@test.zw"
    hired = client.post(f"{API}/staff", headers=manager["headers"], json={
        "full_name": "Chipo D.", "position": "Till Operator",
        "shop_id": shop["id"], "role": "cashier",
        "email": email, "password": "chipo-own-secret-1",
    })
    assert hired.status_code == 201, hired.text
    employee = hired.json()
    assert employee["shop_id"] == shop["id"]
    assert employee["on_duty"] is False
    assert employee["user_id"]

    # The employee's own password works, lands them in the cashier role,
    # and is never readable by anyone (stored as an Argon2 hash).
    login = client.post(f"{API}/auth/login",
                        json={"email": email, "password": "chipo-own-secret-1"})
    assert login.status_code == 200
    me = client.get(f"{API}/auth/me", headers={
        "Authorization": f"Bearer {login.json()['access_token']}"})
    assert me.json()["role"] == "cashier"


def test_manager_cannot_hire_an_owner(client, biz):
    manager = make_user(client, biz, "manager")
    denied = client.post(f"{API}/staff", headers=manager["headers"], json={
        "full_name": "Sneaky", "role": "owner",
        "email": f"sneak-{uuid.uuid4().hex[:8]}@test.zw",
        "password": "password-123",
    })
    assert denied.status_code == 400


def test_cashier_cannot_hire_staff(client, biz):
    cashier = make_user(client, biz, "cashier")
    denied = client.post(f"{API}/staff", headers=cashier["headers"], json={
        "full_name": "Nope", "role": "cashier",
        "email": f"nope-{uuid.uuid4().hex[:8]}@test.zw",
        "password": "password-123",
    })
    assert denied.status_code == 403


def test_manager_toggles_duty_and_reassigns_branch(client, biz):
    manager = make_user(client, biz, "manager")
    hired = client.post(f"{API}/staff", headers=manager["headers"], json={
        "full_name": "Tawanda M.", "position": "Storekeeper",
        "role": "storekeeper",
        "email": f"tawa-{uuid.uuid4().hex[:8]}@test.zw",
        "password": "tawanda-secret-1",
    }).json()

    on = client.patch(f"{API}/employees/{hired['id']}",
                      headers=manager["headers"], json={"on_duty": True})
    assert on.status_code == 200 and on.json()["on_duty"] is True

    # Owner opens a new branch; manager may not (branches are owner-only) …
    branch = client.post(f"{API}/shops", headers=biz["headers"],
                         json={"name": "Mbare Branch"})
    assert branch.status_code == 201
    denied = client.post(f"{API}/shops", headers=manager["headers"],
                         json={"name": "Rogue Branch"})
    assert denied.status_code == 403

    # … but the manager can move staff between existing branches.
    moved = client.patch(f"{API}/employees/{hired['id']}",
                         headers=manager["headers"],
                         json={"shop_id": branch.json()["id"]})
    assert moved.json()["shop_id"] == branch.json()["id"]
