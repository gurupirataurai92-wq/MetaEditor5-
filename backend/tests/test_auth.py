from app.core.security import totp_code

from tests.conftest import API, make_user


def test_register_login_me(client, biz):
    login = client.post(f"{API}/auth/login",
                        json={"email": biz["email"], "password": biz["password"]})
    assert login.status_code == 200
    me = client.get(f"{API}/auth/me", headers={
        "Authorization": f"Bearer {login.json()['access_token']}"})
    assert me.status_code == 200
    assert me.json()["role"] == "owner"


def test_wrong_password_rejected(client, biz):
    resp = client.post(f"{API}/auth/login",
                       json={"email": biz["email"], "password": "wrong-pass"})
    assert resp.status_code == 401


def test_duplicate_registration_rejected(client, biz):
    resp = client.post(f"{API}/auth/register-business", json={
        "business_name": "Dup", "full_name": "Dup", "email": biz["email"],
        "password": "s3curePass!",
    })
    assert resp.status_code == 409


def test_refresh_rotation_is_single_use(client, biz):
    refresh = biz["tokens"]["refresh_token"]
    first = client.post(f"{API}/auth/refresh", json={"refresh_token": refresh})
    assert first.status_code == 200
    replay = client.post(f"{API}/auth/refresh", json={"refresh_token": refresh})
    assert replay.status_code == 401  # rotated: old token revoked


def test_unauthenticated_request_rejected(client):
    assert client.get(f"{API}/products").status_code in (401, 403)


def test_2fa_enable_and_login_flow(client, biz):
    setup = client.post(f"{API}/auth/2fa/setup", headers=biz["headers"])
    assert setup.status_code == 200
    secret = setup.json()["secret"]

    enable = client.post(f"{API}/auth/2fa/enable", headers=biz["headers"],
                         json={"code": totp_code(secret)})
    assert enable.status_code == 200

    # Login without a code is refused; with a valid TOTP it succeeds.
    no_code = client.post(f"{API}/auth/login",
                          json={"email": biz["email"], "password": biz["password"]})
    assert no_code.status_code == 401
    with_code = client.post(f"{API}/auth/login", json={
        "email": biz["email"], "password": biz["password"],
        "totp_code": totp_code(secret)})
    assert with_code.status_code == 200


def test_rbac_cashier_boundaries(client, biz):
    cashier = make_user(client, biz, "cashier")
    # Till operators may add/retire products (serving the counter) …
    created = client.post(f"{API}/products", headers=cashier["headers"],
                          json={"name": "Freezit", "sell_price": "0.50"})
    assert created.status_code == 201
    retired = client.patch(f"{API}/products/{created.json()['id']}",
                           headers=cashier["headers"], json={"is_active": False})
    assert retired.status_code == 200
    # … but never see finance, staffing or monitoring.
    assert client.get(f"{API}/reports/pnl",
                      headers=cashier["headers"]).status_code == 403
    assert client.get(f"{API}/employees",
                      headers=cashier["headers"]).status_code == 403
    assert client.get(f"{API}/reports/cashier-performance",
                      headers=cashier["headers"]).status_code == 403
