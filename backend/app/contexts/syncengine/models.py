from datetime import datetime

from sqlalchemy import BigInteger, DateTime, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, utcnow


class SyncOp(Base):
    """Every applied client operation, keyed by its client-generated op id —
    the dedup table that makes sync idempotent under retries."""

    __tablename__ = "sync_ops"

    op_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    tenant_id: Mapped[str] = mapped_column(String(36), index=True)
    device_id: Mapped[str] = mapped_column(String(64))
    entity: Mapped[str] = mapped_column(String(64))
    action: Mapped[str] = mapped_column(String(32))
    lamport: Mapped[int] = mapped_column(BigInteger, default=0)
    status: Mapped[str] = mapped_column(String(16), default="applied")  # applied|duplicate|error
    detail: Mapped[str | None] = mapped_column(String(255))
    applied_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
