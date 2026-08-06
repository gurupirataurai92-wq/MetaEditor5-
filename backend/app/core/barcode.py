"""EAN-13 barcode number generation and validation.

Rendering the bars (PNG/SVG) is a client/adapter concern; the domain owns
the *number* — including its GS1 check digit.
"""
import secrets

# GS1 prefix reserved for internal/in-store numbering.
INTERNAL_PREFIX = "200"


def ean13_check_digit(digits12: str) -> str:
    if len(digits12) != 12 or not digits12.isdigit():
        raise ValueError("EAN-13 requires exactly 12 digits before the check digit")
    total = sum(int(d) * (3 if i % 2 else 1) for i, d in enumerate(digits12))
    return str((10 - total % 10) % 10)


def generate_ean13(prefix: str = INTERNAL_PREFIX) -> str:
    body = prefix + "".join(str(secrets.randbelow(10)) for _ in range(12 - len(prefix)))
    return body + ean13_check_digit(body)


def is_valid_ean13(code: str) -> bool:
    return (
        len(code) == 13
        and code.isdigit()
        and ean13_check_digit(code[:12]) == code[12]
    )
