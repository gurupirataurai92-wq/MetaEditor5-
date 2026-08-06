import os
import tempfile
import uuid

# Configure the environment BEFORE the app (and its engine) is imported.
_db_path = os.path.join(tempfile.gettempdir(), f"sims_test_{uuid.uuid4().hex}.db")
os.environ["SIMS_DATABASE_URL"] = f"sqlite:///{_db_path}"
os.environ["SIMS_JWT_SECRET"] = "test-secret-key-with-at-least-32-bytes!"

import pytest
from fastapi.testclient import TestClient

from app.main import app  # noqa: E402

API = "/api/v1"


@pytest.fixture(scope="session")
def client():
    with TestClient(app) as c:  # context manager triggers lifespan/init_db
        yield c


def _register(client: TestClient, *, currency: str = "USD") -> dict:
    """Register a fresh business (tenant) and return owner context."""
    email = f"owner-{uuid.uuid4().hex[:10]}@test.zw"
    resp = client.post(f"{API}/auth/register-business", json={
        "business_name": f"Biz {uuid.uuid4().hex[:6]}",
        "full_name": "Test Owner",
        "email": email,
        "password": "s3curePass!",
        "base_currency": currency,
    })
    assert resp.status_code == 201, resp.text
    tokens = resp.json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    me = client.get(f"{API}/auth/me", headers=headers).json()
    return {"email": email, "password": "s3curePass!", "headers": headers,
            "tokens": tokens, "user": me, "tenant_id": me["tenant_id"]}


@pytest.fixture
def biz(client):
    """A fresh tenant per test — natural isolation between tests."""
    return _register(client)


@pytest.fixture
def other_biz(client):
    return _register(client)


def make_user(client, owner_ctx, role: str) -> dict:
    email = f"{role}-{uuid.uuid4().hex[:10]}@test.zw"
    resp = client.post(f"{API}/users", headers=owner_ctx["headers"], json={
        "email": email, "full_name": f"Test {role}", "password": "s3curePass!",
        "role": role,
    })
    assert resp.status_code == 201, resp.text
    login = client.post(f"{API}/auth/login",
                        json={"email": email, "password": "s3curePass!"})
    assert login.status_code == 200, login.text
    return {"email": email,
            "headers": {"Authorization": f"Bearer {login.json()['access_token']}"}}


def make_product(client, ctx, *, name="Mazoe Orange Crush", sell="3.50",
                 cost="2.00", stock=100, tax_class="standard", **extra) -> dict:
    resp = client.post(f"{API}/products", headers=ctx["headers"], json={
        "name": name, "sell_price": sell, "cost_price": cost,
        "tax_class": tax_class, **extra,
    })
    assert resp.status_code == 201, resp.text
    product = resp.json()
    if stock:
        mv = client.post(f"{API}/stock/movements", headers=ctx["headers"], json={
            "product_id": product["id"], "movement_type": "purchase",
            "qty": stock, "unit_cost": cost, "reference": "PO-TEST",
        })
        assert mv.status_code == 201, mv.text
    return product
