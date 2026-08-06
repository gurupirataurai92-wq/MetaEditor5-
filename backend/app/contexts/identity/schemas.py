from pydantic import BaseModel, EmailStr, Field


class RegisterBusinessIn(BaseModel):
    business_name: str = Field(min_length=2, max_length=160)
    full_name: str = Field(min_length=2, max_length=160)
    email: EmailStr
    password: str = Field(min_length=8)
    base_currency: str = "USD"


class LoginIn(BaseModel):
    email: EmailStr
    password: str
    totp_code: str | None = None


class RefreshIn(BaseModel):
    refresh_token: str


class TokenPairOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: str
    tenant_id: str
    email: str
    full_name: str
    role: str
    totp_enabled: bool
    is_active: bool


class UserCreateIn(BaseModel):
    email: EmailStr
    full_name: str
    password: str = Field(min_length=8)
    role: str  # owner | manager | cashier | storekeeper | accountant
    shop_id: str | None = None


class TwoFASetupOut(BaseModel):
    secret: str
    otpauth_uri: str


class TwoFAEnableIn(BaseModel):
    code: str


class ShopIn(BaseModel):
    name: str
    address: str | None = None


class ShopOut(BaseModel):
    id: str
    name: str
    address: str | None
