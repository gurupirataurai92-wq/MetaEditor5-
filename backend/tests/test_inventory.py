from app.core.barcode import ean13_check_digit, generate_ean13, is_valid_ean13

from tests.conftest import API, make_product


def test_ean13_utilities():
    assert ean13_check_digit("400638133393") == "1"  # known GS1 example
    code = generate_ean13()
    assert len(code) == 13 and is_valid_ean13(code)
    assert not is_valid_ean13("4006381333930")  # corrupted check digit


def test_product_gets_sku_and_valid_barcode(client, biz):
    product = make_product(client, biz, stock=0)
    assert product["sku"].startswith("SKU-")
    assert is_valid_ean13(product["barcode"])


def test_stock_ledger_folds_to_on_hand(client, biz):
    product = make_product(client, biz, stock=50)
    client.post(f"{API}/stock/movements", headers=biz["headers"], json={
        "product_id": product["id"], "movement_type": "adjustment", "qty": -3,
        "note": "stock-take shrinkage"})
    levels = client.get(f"{API}/stock/levels", headers=biz["headers"]).json()
    entry = next(l for l in levels if l["product_id"] == product["id"])
    assert entry["on_hand"] == 47


def test_lookup_by_barcode(client, biz):
    product = make_product(client, biz, stock=0)
    found = client.get(f"{API}/products", headers=biz["headers"],
                       params={"barcode": product["barcode"]}).json()
    assert [p["id"] for p in found] == [product["id"]]


def test_tenant_isolation_on_products(client, biz, other_biz):
    product = make_product(client, biz, stock=0)
    # Direct id access from another tenant is a 404, not a leak.
    resp = client.get(f"{API}/products/{product['id']}",
                      headers=other_biz["headers"])
    assert resp.status_code == 404
    assert client.get(f"{API}/products", headers=other_biz["headers"]).json() == []
