from datetime import date
from decimal import Decimal

from pydantic import BaseModel, Field


class CategoryIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class CategoryOut(BaseModel):
    id: str
    name: str


class ProductIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    sku: str | None = None
    barcode: str | None = None
    category_id: str | None = None
    cost_price: Decimal = Decimal("0")
    sell_price: Decimal = Decimal("0")
    currency: str = "USD"
    tax_class: str = "standard"
    reorder_level: int = 0
    batch_no: str | None = None
    expiry_date: date | None = None


class ProductUpdate(BaseModel):
    name: str | None = None
    barcode: str | None = None
    category_id: str | None = None
    cost_price: Decimal | None = None
    sell_price: Decimal | None = None
    currency: str | None = None
    tax_class: str | None = None
    reorder_level: int | None = None
    batch_no: str | None = None
    expiry_date: date | None = None
    is_active: bool | None = None


class ProductOut(BaseModel):
    id: str
    sku: str
    name: str
    barcode: str | None
    category_id: str | None
    cost_price: Decimal
    sell_price: Decimal
    currency: str
    tax_class: str
    reorder_level: int
    batch_no: str | None
    expiry_date: date | None
    is_active: bool
    lamport: int

    model_config = {"from_attributes": True}


class SupplierIn(BaseModel):
    name: str
    phone: str | None = None
    email: str | None = None
    address: str | None = None


class SupplierOut(SupplierIn):
    id: str

    model_config = {"from_attributes": True}


class StockMovementIn(BaseModel):
    product_id: str
    movement_type: str = Field(pattern="^(purchase|adjustment|return)$")
    qty: int
    unit_cost: Decimal | None = None
    reference: str | None = None
    note: str | None = None


class StockMovementOut(BaseModel):
    id: str
    product_id: str
    movement_type: str
    qty: int
    reference: str | None

    model_config = {"from_attributes": True}


class StockLevelOut(BaseModel):
    product_id: str
    name: str
    on_hand: int
    reorder_level: int
    below_reorder: bool
