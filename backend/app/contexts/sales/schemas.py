from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field

PAYMENT_METHODS = "^(cash|ecocash|onemoney|zipit|paynow|bank|card)$"


class SaleLineIn(BaseModel):
    product_id: str
    qty: int = Field(gt=0)
    unit_price: Decimal | None = None  # defaults to the product's sell price


class PaymentIn(BaseModel):
    method: str = Field(pattern=PAYMENT_METHODS)
    amount: Decimal = Field(gt=0)
    currency: str | None = None       # defaults to the sale currency
    exchange_rate: Decimal | None = None
    reference: str | None = None


class SaleIn(BaseModel):
    id: str | None = None             # client-generated UUID → idempotent replays
    customer_id: str | None = None
    shop_id: str | None = None
    currency: str = "USD"
    exchange_rate: Decimal | None = None  # captured rate; None → look up latest
    rate_source: str = "manual"
    captured_at: datetime | None = None
    lamport: int = 0
    lines: list[SaleLineIn] = Field(min_length=1)
    payments: list[PaymentIn] | None = None  # None → single cash payment for the total


class SaleLineOut(BaseModel):
    product_id: str
    product_name: str
    qty: int
    unit_price: Decimal
    line_total: Decimal
    tax_amount: Decimal

    model_config = {"from_attributes": True}


class PaymentOut(BaseModel):
    method: str
    amount: Decimal
    currency: str
    exchange_rate: Decimal
    reference: str | None

    model_config = {"from_attributes": True}


class SaleOut(BaseModel):
    id: str
    customer_id: str | None
    cashier_id: str
    subtotal: Decimal
    tax_amount: Decimal
    total: Decimal
    currency: str
    base_currency: str
    exchange_rate: Decimal
    status: str
    note: str | None
    captured_at: datetime
    lines: list[SaleLineOut]
    payments: list[PaymentOut]


class CustomerIn(BaseModel):
    name: str
    phone: str | None = None
    email: str | None = None


class CustomerOut(CustomerIn):
    id: str
    loyalty_points: int

    model_config = {"from_attributes": True}
