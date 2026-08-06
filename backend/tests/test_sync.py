import uuid

from tests.conftest import API, make_product


def _sale_op(product_id: str, qty: int = 1, lamport: int = 1) -> dict:
    return {
        "op_id": str(uuid.uuid4()),
        "entity": "sale",
        "action": "create",
        "lamport": lamport,
        "payload": {
            "id": str(uuid.uuid4()),
            "currency": "USD",
            "lines": [{"product_id": product_id, "qty": qty}],
        },
    }


def test_sync_applies_offline_sales_and_dedupes_retries(client, biz):
    product = make_product(client, biz, stock=10)
    op = _sale_op(product["id"], qty=2)
    push = {"device_id": "till-1", "cursor": 0, "ops": [op]}

    first = client.post(f"{API}/sync", headers=biz["headers"], json=push)
    assert first.status_code == 200
    assert first.json()["results"][0]["status"] == "applied"

    # Network retry replays the same batch: op is deduped, stock unchanged.
    retry = client.post(f"{API}/sync", headers=biz["headers"], json=push)
    assert retry.json()["results"][0]["status"] == "duplicate"

    levels = client.get(f"{API}/stock/levels", headers=biz["headers"]).json()
    entry = next(l for l in levels if l["product_id"] == product["id"])
    assert entry["on_hand"] == 8  # exactly one application


def test_offline_oversell_is_accepted_and_flagged(client, biz):
    # Two offline tills each sold the last unit: history must be kept.
    product = make_product(client, biz, stock=1)
    ops = [_sale_op(product["id"], qty=1, lamport=1),
           _sale_op(product["id"], qty=1, lamport=2)]
    resp = client.post(f"{API}/sync", headers=biz["headers"],
                       json={"device_id": "till-2", "cursor": 0, "ops": ops})
    statuses = [r["status"] for r in resp.json()["results"]]
    assert statuses == ["applied", "applied"]

    anomalies = client.get(f"{API}/analytics/anomalies", headers=biz["headers"]).json()
    assert any(a["type"] == "oversell" for a in anomalies)


def test_product_upsert_lww_stale_write_loses(client, biz):
    product = make_product(client, biz, name="Original", stock=0)

    def upsert(name: str, lamport: int) -> dict:
        return {"op_id": str(uuid.uuid4()), "entity": "product",
                "action": "upsert", "lamport": lamport,
                "payload": {"id": product["id"], "name": name}}

    # Newer write (lamport 10) lands first; stale write (lamport 4) must lose.
    client.post(f"{API}/sync", headers=biz["headers"], json={
        "device_id": "till-1", "cursor": 0, "ops": [upsert("Newer Name", 10)]})
    client.post(f"{API}/sync", headers=biz["headers"], json={
        "device_id": "till-2", "cursor": 0, "ops": [upsert("Stale Name", 4)]})

    current = client.get(f"{API}/products/{product['id']}",
                         headers=biz["headers"]).json()
    assert current["name"] == "Newer Name"
    assert current["lamport"] == 10


def test_delta_pull_advances_cursor(client, biz):
    product = make_product(client, biz, stock=10)
    first = client.post(f"{API}/sync", headers=biz["headers"], json={
        "device_id": "till-1", "cursor": 0, "ops": []})
    cursor = first.json()["cursor"]
    assert cursor > 0  # product + stock movement changes exist
    assert len(first.json()["server_changes"]) > 0

    # No new activity: pulling from the cursor returns nothing new.
    second = client.post(f"{API}/sync", headers=biz["headers"], json={
        "device_id": "till-1", "cursor": cursor, "ops": []})
    assert second.json()["server_changes"] == []
    assert second.json()["cursor"] == cursor

    # New sale appears in the next delta.
    client.post(f"{API}/sales", headers=biz["headers"], json={
        "lines": [{"product_id": product["id"], "qty": 1}]})
    third = client.post(f"{API}/sync", headers=biz["headers"], json={
        "device_id": "till-1", "cursor": cursor, "ops": []})
    entities = {c["entity"] for c in third.json()["server_changes"]}
    assert "sale" in entities


def test_sync_change_feed_is_tenant_isolated(client, biz, other_biz):
    product = make_product(client, biz, stock=5)
    pull = client.post(f"{API}/sync", headers=other_biz["headers"], json={
        "device_id": "till-x", "cursor": 0, "ops": []})
    changes = pull.json()["server_changes"]
    # The other tenant sees only its own records (e.g. its registration) —
    # nothing from the first tenant may leak into its feed.
    assert all(c["entity_id"] != product["id"] for c in changes)
    assert all(c["entity"] not in ("product", "stock_movement", "sale")
               for c in changes)
