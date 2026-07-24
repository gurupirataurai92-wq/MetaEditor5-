"""Database engine, session and declarative base.

PostgreSQL is the production target (with row-level security applied by
`infra/postgres/rls.sql`); SQLite is supported for development and tests.
Tenant isolation is *always* enforced in the service layer by filtering on
``tenant_id``; RLS is the defence-in-depth second layer on PostgreSQL.
"""
from collections.abc import Iterator
from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.core.config import get_settings

settings = get_settings()

engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False} if settings.database_url.startswith("sqlite") else {},
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def new_id() -> str:
    return str(uuid4())


def utcnow() -> datetime:
    """Naive UTC timestamp (portable across SQLite and PostgreSQL)."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def get_db() -> Iterator[Session]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    # Import all model modules so metadata is complete before create_all.
    from app.core import audit  # noqa: F401
    from app.contexts.identity import models as identity_models  # noqa: F401
    from app.contexts.inventory import models as inventory_models  # noqa: F401
    from app.contexts.sales import models as sales_models  # noqa: F401
    from app.contexts.finance import models as finance_models  # noqa: F401
    from app.contexts.syncengine import models as sync_models  # noqa: F401
    from app.contexts.hr import models as hr_models  # noqa: F401
    from app.contexts.orders import models as orders_models  # noqa: F401

    Base.metadata.create_all(bind=engine)
