from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import AuthContext, get_auth, require
from app.contexts.hr.models import Employee

router = APIRouter(tags=["hr"])


class EmployeeIn(BaseModel):
    full_name: str
    position: str | None = None
    salary: Decimal = Decimal("0")
    currency: str = "USD"
    hired_at: date | None = None
    user_id: str | None = None


class EmployeeOut(EmployeeIn):
    id: str

    model_config = {"from_attributes": True}


@router.post("/employees", response_model=EmployeeOut, status_code=201,
             dependencies=[Depends(require("employees.create"))])
def create_employee(payload: EmployeeIn, auth: AuthContext = Depends(get_auth),
                    db: Session = Depends(get_db)):
    employee = Employee(tenant_id=auth.tenant_id, **payload.model_dump())
    db.add(employee)
    db.commit()
    return EmployeeOut.model_validate(employee)


@router.get("/employees", response_model=list[EmployeeOut],
            dependencies=[Depends(require("employees.read"))])
def list_employees(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    rows = db.scalars(select(Employee).where(Employee.tenant_id == auth.tenant_id)).all()
    return [EmployeeOut.model_validate(e) for e in rows]
