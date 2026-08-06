from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.deps import AuthContext, get_auth, require
from app.contexts.analytics import assistant, service

router = APIRouter(tags=["analytics"])


class AskIn(BaseModel):
    question: str = Field(min_length=3, max_length=500)


@router.get("/analytics/forecast", dependencies=[Depends(require("analytics.read"))])
def forecast(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db),
             product_id: str | None = None, days_ahead: int = 14, window: int = 60):
    return service.forecast(db, auth.tenant_id, days_ahead=min(days_ahead, 90),
                            window=min(window, 365), product_id=product_id)


@router.get("/analytics/reorder-suggestions",
            dependencies=[Depends(require("analytics.read"))])
def reorder(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db),
            lead_time_days: int = 7):
    return service.reorder_suggestions(db, auth.tenant_id,
                                       lead_time_days=min(lead_time_days, 60))


@router.get("/analytics/anomalies", dependencies=[Depends(require("analytics.read"))])
def anomalies(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db),
              window: int = 30):
    return service.anomalies(db, auth.tenant_id, window=min(window, 180))


@router.post("/assistant/ask", dependencies=[Depends(require("analytics.read"))])
def ask(payload: AskIn, auth: AuthContext = Depends(get_auth),
        db: Session = Depends(get_db)):
    return assistant.ask(db, auth.tenant_id, payload.question)
