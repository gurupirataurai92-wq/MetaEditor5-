"""Offline-first synchronisation endpoint (dissertation §4.6).

Push: clients submit their outbox — operations with client-generated UUIDs
and Lamport clocks. Dedup by op id makes retries idempotent; immutable
events (sales) are appended via the same domain service as the online POS
(with oversell allowed and flagged); mutable master data (products) merges
last-writer-wins on the Lamport clock.

Pull: clients receive all change-log rows after their cursor (delta sync),
plus a new cursor.
"""
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import audit
from app.core.audit import ChangeLog
from app.core.db import get_db, utcnow
from app.core.deps import AuthContext, get_auth, require
from app.contexts.inventory.models import Product
from app.contexts.sales.schemas import SaleIn
from app.contexts.sales.service import create_sale
from app.contexts.syncengine.models import SyncOp

router = APIRouter(tags=["sync"])


class SyncOpIn(BaseModel):
    op_id: str
    entity: str  # sale | product
    action: str  # create | upsert
    lamport: int = 0
    payload: dict[str, Any]


class SyncPushIn(BaseModel):
    device_id: str
    cursor: int = 0
    ops: list[SyncOpIn] = Field(default_factory=list)


@router.post("/sync", dependencies=[Depends(require("sync.push"))])
def sync(payload: SyncPushIn, auth: AuthContext = Depends(get_auth),
         db: Session = Depends(get_db)):
    results = []
    # Apply in Lamport order so causally-later writes win deterministically.
    for op in sorted(payload.ops, key=lambda o: o.lamport):
        if db.get(SyncOp, op.op_id) is not None:
            results.append({"op_id": op.op_id, "status": "duplicate"})
            continue
        try:
            _apply(db, auth, op)
            status_ = "applied"
            detail = None
        except HTTPException as exc:
            db.rollback()
            status_ = "error"
            detail = str(exc.detail)[:255]
        db.add(SyncOp(op_id=op.op_id, tenant_id=auth.tenant_id,
                      device_id=payload.device_id, entity=op.entity,
                      action=op.action, lamport=op.lamport,
                      status=status_, detail=detail))
        db.commit()
        results.append({"op_id": op.op_id, "status": status_,
                        **({"detail": detail} if detail else {})})

    # Delta pull: everything after the client's cursor.
    changes = db.scalars(
        select(ChangeLog)
        .where(ChangeLog.tenant_id == auth.tenant_id, ChangeLog.seq > payload.cursor)
        .order_by(ChangeLog.seq)
        .limit(500)
    ).all()
    new_cursor = changes[-1].seq if changes else payload.cursor
    return {
        "results": results,
        "server_changes": [
            {"seq": c.seq, "entity": c.entity, "entity_id": c.entity_id,
             "action": c.action, "payload": c.payload}
            for c in changes
        ],
        "cursor": new_cursor,
    }


def _apply(db: Session, auth: AuthContext, op: SyncOpIn) -> None:
    if op.entity == "sale" and op.action == "create":
        sale_in = SaleIn.model_validate({**op.payload, "lamport": op.lamport})
        sale, created = create_sale(
            db, tenant_id=auth.tenant_id, cashier_id=auth.user_id,
            payload=sale_in, allow_oversell=True,  # offline reality: accept & flag
        )
        if created:
            sale.synced_at = utcnow()
            db.commit()
    elif op.entity == "product" and op.action == "upsert":
        _upsert_product_lww(db, auth, op)
    else:
        raise HTTPException(400, f"Unsupported op: {op.entity}.{op.action}")


def _upsert_product_lww(db: Session, auth: AuthContext, op: SyncOpIn) -> None:
    data = dict(op.payload)
    product_id = data.pop("id", None)
    if product_id is None:
        raise HTTPException(400, "product upsert requires id")
    product = db.get(Product, product_id)
    if product is not None and product.tenant_id != auth.tenant_id:
        raise HTTPException(409, "Product id collision")

    editable = {"name", "barcode", "category_id", "cost_price", "sell_price",
                "currency", "tax_class", "reorder_level", "batch_no", "is_active"}
    if product is None:
        product = Product(id=product_id, tenant_id=auth.tenant_id,
                          sku=data.get("sku") or f"SKU-{product_id[:8].upper()}",
                          lamport=op.lamport,
                          **{k: v for k, v in data.items() if k in editable})
        db.add(product)
        action = "create"
    elif op.lamport > product.lamport:  # last-writer-wins
        for key, value in data.items():
            if key in editable:
                setattr(product, key, value)
        product.lamport = op.lamport
        action = "update"
    else:
        return  # stale write loses; nothing to record
    audit.record(db, tenant_id=auth.tenant_id, actor_id=auth.user_id, action=action,
                 entity="product", entity_id=product_id,
                 data={"via": "sync", "lamport": op.lamport})
    db.commit()
