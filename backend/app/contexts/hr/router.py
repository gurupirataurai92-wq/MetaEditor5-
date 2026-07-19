from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import audit
from app.core.db import get_db
from app.core.deps import AuthContext, get_auth, require
from app.contexts.hr.models import Employee
from app.contexts.identity.schemas import UserCreateIn
from app.contexts.identity.service import create_user

router = APIRouter(tags=["hr"])

# Roles a manager may hire into. Owner accounts are never created this way.
HIREABLE_ROLES = {"cashier", "storekeeper", "accountant", "manager"}


class EmployeeIn(BaseModel):
    full_name: str
    position: str | None = None
    shop_id: str | None = None
    salary: Decimal = Decimal("0")
    currency: str = "USD"
    hired_at: date | None = None
    user_id: str | None = None


class EmployeeUpdate(BaseModel):
    position: str | None = None
    shop_id: str | None = None
    on_duty: bool | None = None
    salary: Decimal | None = None


class StaffIn(BaseModel):
    """Hire an employee *and* create their login in one step.

    The password is typed by the employee themself at hiring and stored only
    as an Argon2 hash — confidential to them; no one can read it back.
    """

    full_name: str
    position: str | None = None
    shop_id: str | None = None
    role: str
    email: EmailStr
    password: str = Field(min_length=8)
    salary: Decimal = Decimal("0")
    currency: str = "USD"


class EmployeeOut(BaseModel):
    id: str
    full_name: str
    position: str | None
    shop_id: str | None
    on_duty: bool
    salary: Decimal
    currency: str
    hired_at: date | None
    user_id: str | None

    model_config = {"from_attributes": True}


def _get_employee(db: Session, tenant_id: str, employee_id: str) -> Employee:
    employee = db.get(Employee, employee_id)
    if employee is None or employee.tenant_id != tenant_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Employee not found")
    return employee


@router.post("/employees", response_model=EmployeeOut, status_code=201,
             dependencies=[Depends(require("employees.create"))])
def create_employee(payload: EmployeeIn, auth: AuthContext = Depends(get_auth),
                    db: Session = Depends(get_db)):
    employee = Employee(tenant_id=auth.tenant_id, **payload.model_dump())
    db.add(employee)
    db.flush()
    audit.record(db, tenant_id=auth.tenant_id, actor_id=auth.user_id, action="create",
                 entity="employee", entity_id=employee.id,
                 data={"full_name": employee.full_name})
    db.commit()
    return EmployeeOut.model_validate(employee)


@router.post("/staff", response_model=EmployeeOut, status_code=201,
             dependencies=[Depends(require("employees.create")),
                           Depends(require("users.create"))])
def hire_staff(payload: StaffIn, auth: AuthContext = Depends(get_auth),
               db: Session = Depends(get_db)):
    if payload.role not in HIREABLE_ROLES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST,
                            f"Role must be one of: {', '.join(sorted(HIREABLE_ROLES))}")
    user = create_user(db, auth.tenant_id, auth.user_id, UserCreateIn(
        email=payload.email, full_name=payload.full_name,
        password=payload.password, role=payload.role, shop_id=payload.shop_id,
    ))
    employee = Employee(
        tenant_id=auth.tenant_id, user_id=user.id, shop_id=payload.shop_id,
        full_name=payload.full_name, position=payload.position,
        salary=payload.salary, currency=payload.currency, hired_at=date.today(),
    )
    db.add(employee)
    db.flush()
    audit.record(db, tenant_id=auth.tenant_id, actor_id=auth.user_id, action="hire",
                 entity="employee", entity_id=employee.id,
                 data={"full_name": employee.full_name, "role": payload.role,
                       "shop_id": payload.shop_id})
    db.commit()
    return EmployeeOut.model_validate(employee)


@router.patch("/employees/{employee_id}", response_model=EmployeeOut,
              dependencies=[Depends(require("employees.update"))])
def update_employee(employee_id: str, payload: EmployeeUpdate,
                    auth: AuthContext = Depends(get_auth),
                    db: Session = Depends(get_db)):
    employee = _get_employee(db, auth.tenant_id, employee_id)
    changes = payload.model_dump(exclude_unset=True)
    for field, value in changes.items():
        setattr(employee, field, value)
    audit.record(db, tenant_id=auth.tenant_id, actor_id=auth.user_id, action="update",
                 entity="employee", entity_id=employee.id, data=changes)
    db.commit()
    return EmployeeOut.model_validate(employee)


@router.get("/employees", response_model=list[EmployeeOut],
            dependencies=[Depends(require("employees.read"))])
def list_employees(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    rows = db.scalars(select(Employee).where(Employee.tenant_id == auth.tenant_id)).all()
    return [EmployeeOut.model_validate(e) for e in rows]
