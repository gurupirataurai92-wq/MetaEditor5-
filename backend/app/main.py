"""SIMS AI — Smart Informal Business Management Ecosystem.

REST API entrypoint: a modular monolith of DDD bounded contexts
(identity, inventory, sales, finance, sync, analytics, HR) behind a
single OpenAPI surface. Run with:

    uvicorn app.main:app --reload
"""
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import get_settings
from app.core.db import init_db
from app.contexts.analytics.router import router as analytics_router
from app.contexts.finance.router import router as finance_router
from app.contexts.hr.router import router as hr_router
from app.contexts.identity.router import router as identity_router
from app.contexts.inventory.router import router as inventory_router
from app.contexts.sales.router import router as sales_router
from app.contexts.syncengine.router import router as sync_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="SIMS AI API",
        version="1.0.0",
        description=(
            "Smart Informal Business Management Ecosystem — offline-first, "
            "AI-augmented business management for Zimbabwean SMEs. "
            "Multi-tenant, RBAC-secured, multi-currency (ZiG/USD) with "
            "transaction-time exchange-rate capture."
        ),
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[o.strip() for o in settings.cors_origins.split(",")],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    for router in (identity_router, inventory_router, sales_router,
                   finance_router, sync_router, analytics_router, hr_router):
        app.include_router(router, prefix="/api/v1")

    @app.get("/health", tags=["system"])
    def health():
        return {"status": "ok", "service": settings.app_name}

    return app


app = create_app()
