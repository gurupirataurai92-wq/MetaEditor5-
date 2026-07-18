"""Security primitives: Argon2 password hashing, JWT tokens, TOTP 2FA (RFC 6238)."""
import base64
import hashlib
import hmac
import secrets
import struct
import time
from datetime import timedelta
from typing import Any

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

from app.core.config import get_settings
from app.core.db import utcnow

_hasher = PasswordHasher()


# ---------------------------------------------------------------- passwords
def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _hasher.verify(password_hash, password)
    except VerifyMismatchError:
        return False


# ---------------------------------------------------------------------- JWT
def create_access_token(*, user_id: str, tenant_id: str, role: str, permissions: list[str]) -> str:
    settings = get_settings()
    now = utcnow()
    payload = {
        "sub": user_id,
        "tid": tenant_id,
        "role": role,
        "perms": permissions,
        "type": "access",
        "iat": now,
        "exp": now + timedelta(minutes=settings.access_token_ttl_minutes),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> dict[str, Any] | None:
    settings = get_settings()
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except jwt.PyJWTError:
        return None


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def token_digest(token: str) -> str:
    """Refresh tokens are stored only as SHA-256 digests (never in clear)."""
    return hashlib.sha256(token.encode()).hexdigest()


# ------------------------------------------------------------- TOTP (2FA)
def generate_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode()


def _hotp(secret_b32: str, counter: int, digits: int = 6) -> str:
    key = base64.b32decode(secret_b32)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    code = (struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF) % (10**digits)
    return str(code).zfill(digits)


def totp_code(secret_b32: str, at: float | None = None, step: int = 30) -> str:
    return _hotp(secret_b32, int((at if at is not None else time.time()) // step))


def verify_totp(secret_b32: str, code: str, window: int = 1) -> bool:
    """Accept the current period ± ``window`` periods of clock drift."""
    counter = int(time.time() // 30)
    return any(
        hmac.compare_digest(_hotp(secret_b32, counter + offset), code)
        for offset in range(-window, window + 1)
    )


def otpauth_uri(secret_b32: str, account: str, issuer: str = "SIMS AI") -> str:
    return f"otpauth://totp/{issuer}:{account}?secret={secret_b32}&issuer={issuer}"
