from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.contexts.inventory.models import Product, StockMovement


def on_hand(db: Session, tenant_id: str, product_id: str,
            shop_id: str | None = None) -> int:
    """Stock on hand as a fold over the movement ledger. When ``shop_id`` is
    given, only that branch's movements count (per-branch inventory)."""
    conditions = [
        StockMovement.tenant_id == tenant_id,
        StockMovement.product_id == product_id,
    ]
    if shop_id is not None:
        conditions.append(StockMovement.shop_id == shop_id)
    total = db.scalar(
        select(func.coalesce(func.sum(StockMovement.qty), 0)).where(*conditions)
    )
    return int(total or 0)


def get_product(db: Session, tenant_id: str, product_id: str) -> Product | None:
    product = db.get(Product, product_id)
    if product is None or product.tenant_id != tenant_id:
        return None
    return product
