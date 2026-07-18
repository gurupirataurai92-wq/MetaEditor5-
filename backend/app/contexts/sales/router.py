from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import AuthContext, get_auth, require
from app.core.pdfgen import text_pdf
from app.contexts.identity.models import Tenant
from app.contexts.sales import service
from app.contexts.sales.models import Customer, Payment, Sale, SaleLine
from app.contexts.sales.schemas import (
    CustomerIn,
    CustomerOut,
    PaymentOut,
    SaleIn,
    SaleLineOut,
    SaleOut,
)

router = APIRouter(tags=["sales"])


def _sale_out(db: Session, sale: Sale) -> SaleOut:
    lines = db.scalars(select(SaleLine).where(SaleLine.sale_id == sale.id)).all()
    payments = db.scalars(select(Payment).where(Payment.sale_id == sale.id)).all()
    return SaleOut(
        id=sale.id, customer_id=sale.customer_id, cashier_id=sale.cashier_id,
        subtotal=sale.subtotal, tax_amount=sale.tax_amount, total=sale.total,
        currency=sale.currency, base_currency=sale.base_currency,
        exchange_rate=sale.exchange_rate, status=sale.status, note=sale.note,
        captured_at=sale.captured_at,
        lines=[SaleLineOut.model_validate(l) for l in lines],
        payments=[PaymentOut.model_validate(p) for p in payments],
    )


def _get_sale(db: Session, tenant_id: str, sale_id: str) -> Sale:
    sale = db.get(Sale, sale_id)
    if sale is None or sale.tenant_id != tenant_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Sale not found")
    return sale


@router.post("/sales", response_model=SaleOut,
             dependencies=[Depends(require("sales.create"))])
def create_sale(payload: SaleIn, response: Response,
                auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    sale, created = service.create_sale(
        db, tenant_id=auth.tenant_id, cashier_id=auth.user_id, payload=payload,
    )
    response.status_code = status.HTTP_201_CREATED if created else status.HTTP_200_OK
    return _sale_out(db, sale)


@router.get("/sales", response_model=list[SaleOut],
            dependencies=[Depends(require("sales.read"))])
def list_sales(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db),
               limit: int = 50):
    sales = db.scalars(
        select(Sale).where(Sale.tenant_id == auth.tenant_id)
        .order_by(Sale.captured_at.desc()).limit(min(limit, 200))
    ).all()
    return [_sale_out(db, s) for s in sales]


@router.get("/sales/{sale_id}", response_model=SaleOut,
            dependencies=[Depends(require("sales.read"))])
def get_sale(sale_id: str, auth: AuthContext = Depends(get_auth),
             db: Session = Depends(get_db)):
    return _sale_out(db, _get_sale(db, auth.tenant_id, sale_id))


@router.post("/sales/{sale_id}/void", response_model=SaleOut,
             dependencies=[Depends(require("sales.void"))])
def void_sale(sale_id: str, auth: AuthContext = Depends(get_auth),
              db: Session = Depends(get_db)):
    sale = service.void_sale(db, tenant_id=auth.tenant_id, actor_id=auth.user_id,
                             sale_id=sale_id)
    return _sale_out(db, sale)


@router.get("/sales/{sale_id}/receipt.pdf",
            dependencies=[Depends(require("sales.read"))])
def receipt_pdf(sale_id: str, auth: AuthContext = Depends(get_auth),
                db: Session = Depends(get_db)):
    sale = _get_sale(db, auth.tenant_id, sale_id)
    tenant = db.get(Tenant, auth.tenant_id)
    lines = db.scalars(select(SaleLine).where(SaleLine.sale_id == sale.id)).all()
    payments = db.scalars(select(Payment).where(Payment.sale_id == sale.id)).all()

    text = [
        tenant.name.upper(),
        "RECEIPT",
        f"No: {sale.id[:8].upper()}   {sale.captured_at:%Y-%m-%d %H:%M}",
        "-" * 42,
    ]
    for l in lines:
        text.append(f"{l.product_name[:24]:<24} x{l.qty:<3} {l.line_total:>9}")
    text += [
        "-" * 42,
        f"{'Subtotal (ex VAT)':<28} {sale.subtotal:>12}",
        f"{'VAT (incl.)':<28} {sale.tax_amount:>12}",
        f"{'TOTAL ' + sale.currency:<28} {sale.total:>12}",
        f"Rate: 1 {sale.currency} = {sale.exchange_rate} {sale.base_currency}",
        "-" * 42,
    ]
    for p in payments:
        text.append(f"Paid {p.method:<10} {p.amount} {p.currency}")
    text += ["", "Thank you for your business!", "Powered by SIMS AI"]

    pdf = text_pdf(text, title=f"Receipt {sale.id[:8]}")
    return Response(content=pdf, media_type="application/pdf")


# -------------------------------------------------------------- customers
@router.post("/customers", response_model=CustomerOut, status_code=201,
             dependencies=[Depends(require("customers.create"))])
def create_customer(payload: CustomerIn, auth: AuthContext = Depends(get_auth),
                    db: Session = Depends(get_db)):
    customer = Customer(tenant_id=auth.tenant_id, **payload.model_dump())
    db.add(customer)
    db.commit()
    return CustomerOut.model_validate(customer)


@router.get("/customers", response_model=list[CustomerOut],
            dependencies=[Depends(require("customers.read"))])
def list_customers(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    rows = db.scalars(select(Customer).where(Customer.tenant_id == auth.tenant_id)).all()
    return [CustomerOut.model_validate(c) for c in rows]


@router.get("/customers/{customer_id}", response_model=CustomerOut,
            dependencies=[Depends(require("customers.read"))])
def get_customer(customer_id: str, auth: AuthContext = Depends(get_auth),
                 db: Session = Depends(get_db)):
    customer = db.get(Customer, customer_id)
    if customer is None or customer.tenant_id != auth.tenant_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Customer not found")
    return CustomerOut.model_validate(customer)
