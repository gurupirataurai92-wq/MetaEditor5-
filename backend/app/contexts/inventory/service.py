from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.contexts.inventory.models import Product, StockMovement


def on_hand(db: Session, tenant_id: str, product_id: str) -> int:
    total = db.scalar(
        select(func.coalesce(func.sum(StockMovement.qty), 0)).where(
            StockMovement.tenant_id == tenant_id,
            StockMovement.product_id == product_id,
        )
    )
    return int(total or 0)


def get_product(db: Session, tenant_id: str, product_id: str) -> Product | None:
    product = db.get(Product, product_id)
    if product is None or product.tenant_id != tenant_id:
        return None
    return product
