from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core import audit
from app.core.barcode import generate_ean13, is_valid_ean13
from app.core.db import get_db, new_id
from app.core.deps import AuthContext, get_auth, require
from app.contexts.inventory import service
from app.contexts.inventory.models import Category, Product, StockMovement, Supplier
from app.contexts.inventory.schemas import (
    CategoryIn,
    CategoryOut,
    ProductIn,
    ProductOut,
    ProductUpdate,
    StockLevelOut,
    StockMovementIn,
    StockMovementOut,
    SupplierIn,
    SupplierOut,
)

router = APIRouter(tags=["inventory"])


# ------------------------------------------------------------- categories
@router.post("/categories", response_model=CategoryOut, status_code=201,
             dependencies=[Depends(require("categories.create"))])
def create_category(payload: CategoryIn, auth: AuthContext = Depends(get_auth),
                    db: Session = Depends(get_db)):
    cat = Category(tenant_id=auth.tenant_id, name=payload.name)
    db.add(cat)
    db.commit()
    return CategoryOut(id=cat.id, name=cat.name)


@router.get("/categories", response_model=list[CategoryOut],
            dependencies=[Depends(require("products.read"))])
def list_categories(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    rows = db.scalars(select(Category).where(Category.tenant_id == auth.tenant_id)).all()
    return [CategoryOut(id=c.id, name=c.name) for c in rows]


# --------------------------------------------------------------- products
@router.post("/products", response_model=ProductOut, status_code=201,
             dependencies=[Depends(require("products.create"))])
def create_product(payload: ProductIn, auth: AuthContext = Depends(get_auth),
                   db: Session = Depends(get_db)):
    if payload.barcode and not is_valid_ean13(payload.barcode):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid EAN-13 barcode")
    product = Product(
        tenant_id=auth.tenant_id,
        sku=payload.sku or f"SKU-{new_id()[:8].upper()}",
        barcode=payload.barcode or generate_ean13(),
        **payload.model_dump(exclude={"sku", "barcode"}),
    )
    db.add(product)
    db.flush()
    audit.record(db, tenant_id=auth.tenant_id, actor_id=auth.user_id, action="create",
                 entity="product", entity_id=product.id,
                 data={"name": product.name, "sku": product.sku})
    db.commit()
    return ProductOut.model_validate(product)


@router.get("/products", response_model=list[ProductOut],
            dependencies=[Depends(require("products.read"))])
def list_products(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db),
                  barcode: str | None = None):
    q = select(Product).where(Product.tenant_id == auth.tenant_id)
    if barcode:
        q = q.where(Product.barcode == barcode)
    return [ProductOut.model_validate(p) for p in db.scalars(q).all()]


@router.get("/products/{product_id}", response_model=ProductOut,
            dependencies=[Depends(require("products.read"))])
def get_product(product_id: str, auth: AuthContext = Depends(get_auth),
                db: Session = Depends(get_db)):
    product = service.get_product(db, auth.tenant_id, product_id)
    if product is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Product not found")
    return ProductOut.model_validate(product)


@router.patch("/products/{product_id}", response_model=ProductOut,
              dependencies=[Depends(require("products.update"))])
def update_product(product_id: str, payload: ProductUpdate,
                   auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    product = service.get_product(db, auth.tenant_id, product_id)
    if product is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Product not found")
    changes = payload.model_dump(exclude_unset=True)
    for field, value in changes.items():
        setattr(product, field, value)
    product.lamport += 1
    audit.record(db, tenant_id=auth.tenant_id, actor_id=auth.user_id, action="update",
                 entity="product", entity_id=product.id, data=changes)
    db.commit()
    return ProductOut.model_validate(product)


# ------------------------------------------------------------------ stock
@router.post("/stock/movements", response_model=StockMovementOut, status_code=201,
             dependencies=[Depends(require("stock.create"))])
def create_movement(payload: StockMovementIn, auth: AuthContext = Depends(get_auth),
                    db: Session = Depends(get_db)):
    product = service.get_product(db, auth.tenant_id, payload.product_id)
    if product is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Product not found")
    movement = StockMovement(tenant_id=auth.tenant_id, created_by=auth.user_id,
                             **payload.model_dump())
    db.add(movement)
    db.flush()
    audit.record(db, tenant_id=auth.tenant_id, actor_id=auth.user_id, action="create",
                 entity="stock_movement", entity_id=movement.id,
                 data=payload.model_dump())
    db.commit()
    return StockMovementOut.model_validate(movement)


@router.get("/stock/levels", response_model=list[StockLevelOut],
            dependencies=[Depends(require("stock.read"))])
def stock_levels(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    on_hand_sq = (
        select(StockMovement.product_id,
               func.coalesce(func.sum(StockMovement.qty), 0).label("on_hand"))
        .where(StockMovement.tenant_id == auth.tenant_id)
        .group_by(StockMovement.product_id)
        .subquery()
    )
    rows = db.execute(
        select(Product, func.coalesce(on_hand_sq.c.on_hand, 0))
        .outerjoin(on_hand_sq, on_hand_sq.c.product_id == Product.id)
        .where(Product.tenant_id == auth.tenant_id, Product.is_active)
    ).all()
    return [
        StockLevelOut(product_id=p.id, name=p.name, on_hand=int(qty),
                      reorder_level=p.reorder_level,
                      below_reorder=int(qty) <= p.reorder_level)
        for p, qty in rows
    ]


# -------------------------------------------------------------- suppliers
@router.post("/suppliers", response_model=SupplierOut, status_code=201,
             dependencies=[Depends(require("suppliers.create"))])
def create_supplier(payload: SupplierIn, auth: AuthContext = Depends(get_auth),
                    db: Session = Depends(get_db)):
    supplier = Supplier(tenant_id=auth.tenant_id, **payload.model_dump())
    db.add(supplier)
    db.commit()
    return SupplierOut.model_validate(supplier)


@router.get("/suppliers", response_model=list[SupplierOut],
            dependencies=[Depends(require("suppliers.read"))])
def list_suppliers(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    rows = db.scalars(select(Supplier).where(Supplier.tenant_id == auth.tenant_id)).all()
    return [SupplierOut.model_validate(s) for s in rows]
