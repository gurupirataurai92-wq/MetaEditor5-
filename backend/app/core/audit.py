"""Cross-cutting audit trail and synchronisation change log.

``AuditLog`` answers *who did what, when* (compliance, fraud review).
``ChangeLog`` is the monotonically increasing feed clients pull during
delta synchronisation (cursor = last seen ``seq``).
"""
from datetime import datetime
from typing import Any

from fastapi.encoders import jsonable_encoder
from sqlalchemy import JSON, BigInteger, DateTime, Integer, String
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.core.db import Base, new_id, utcnow


class AuditLog(Base):
    __tablename__ = "audit_log"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    actor_id: Mapped[str | None] = mapped_column(String(36))
    action: Mapped[str] = mapped_column(String(64))
    entity: Mapped[str] = mapped_column(String(64))
    entity_id: Mapped[str] = mapped_column(String(64))
    data: Mapped[dict | None] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class ChangeLog(Base):
    __tablename__ = "change_log"

    # SQLite only autoincrements INTEGER primary keys, hence the variant.
    seq: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer(), "sqlite"),
        primary_key=True,
        autoincrement=True,
    )
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    entity: Mapped[str] = mapped_column(String(64))
    entity_id: Mapped[str] = mapped_column(String(64))
    action: Mapped[str] = mapped_column(String(64))
    payload: Mapped[dict | None] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


def record(
    db: Session,
    *,
    tenant_id: str,
    actor_id: str | None,
    action: str,
    entity: str,
    entity_id: str,
    data: Any = None,
) -> None:
    payload = jsonable_encoder(data) if data is not None else None
    db.add(AuditLog(tenant_id=tenant_id, actor_id=actor_id, action=action,
                    entity=entity, entity_id=entity_id, data=payload))
    db.add(ChangeLog(tenant_id=tenant_id, entity=entity, entity_id=entity_id,
                     action=action, payload=payload))
