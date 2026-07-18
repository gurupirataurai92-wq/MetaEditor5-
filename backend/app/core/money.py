"""Exact-decimal money arithmetic.

All monetary amounts are ``Decimal`` end to end (never binary floats) and
quantised to 2 dp for money, 6 dp for exchange rates — the invariant that
keeps multi-currency records exact (dissertation §4.5.2).

Rate semantics: ``exchange_rate`` is the amount of *base currency* per one
unit of the transaction currency (e.g. ZWG→USD 0.037 means 1 ZWG = 0.037 USD).
"""
from decimal import ROUND_HALF_UP, Decimal

CENTS = Decimal("0.01")
RATE_DP = Decimal("0.000001")


def money(value) -> Decimal:
    return Decimal(str(value)).quantize(CENTS, rounding=ROUND_HALF_UP)


def rate(value) -> Decimal:
    return Decimal(str(value)).quantize(RATE_DP, rounding=ROUND_HALF_UP)


def to_base(amount, exchange_rate) -> Decimal:
    """Convert a transaction-currency amount to base using the captured rate."""
    return money(Decimal(str(amount)) * Decimal(str(exchange_rate)))


def vat_portion(gross, vat_rate: Decimal) -> Decimal:
    """VAT contained in a VAT-inclusive price: gross × r/(1+r).

    Retail prices in Zimbabwe are customarily VAT-inclusive, so the system
    treats sell prices as gross and extracts the VAT portion for ZIMRA
    reporting rather than adding VAT on top.
    """
    return money(Decimal(str(gross)) * vat_rate / (Decimal("1") + vat_rate))
