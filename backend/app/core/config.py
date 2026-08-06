"""Application settings — twelve-factor: all config comes from the environment."""
from decimal import Decimal
from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "SIMS AI"
    database_url: str = "sqlite:///./sims.db"

    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    access_token_ttl_minutes: int = 15
    refresh_token_ttl_days: int = 30

    # ZiG is ISO-coded ZWG; USD is the default reporting (base) currency.
    base_currency: str = "USD"
    # ZIMRA standard VAT rate; parameterised so statutory changes are config, not code.
    vat_rate: Decimal = Decimal("0.15")

    cors_origins: str = "*"

    model_config = {"env_prefix": "SIMS_", "env_file": ".env"}


@lru_cache
def get_settings() -> Settings:
    return Settings()
