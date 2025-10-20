from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache


@dataclass(frozen=True)
class Settings:
    app_name: str
    app_version: str
    ddb_table: str
    secret_name: str
    cache_ttl_seconds: int
    default_user_id: str
    cb_base_url: str
    cors_allow_origin: str
    cors_allow_headers: str
    cors_allow_methods: str


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    ddb = os.getenv("DDB_TABLE", "iqana_holdings")
    secret = os.getenv("CB_SECRET_NAME", "iqana_coinbase_exchange_sandbox")
    if not ddb or not secret:
        raise RuntimeError()
    return Settings(
        app_name=os.getenv("APP_NAME", "iqana-api"),
        app_version=os.getenv("APP_VERSION", "0.1.0"),
        ddb_table=ddb,
        secret_name=secret,
        cache_ttl_seconds=int(os.getenv("CACHE_TTL_SECONDS", "180")),
        default_user_id=os.getenv("DEFAULT_USER_ID", "demo-user"),
        cb_base_url=os.getenv("CB_BASE_URL", "https://api-public.sandbox.exchange.coinbase.com"),
        cors_allow_origin=os.getenv("CORS_ALLOW_ORIGIN", "*"),
        cors_allow_headers=os.getenv("CORS_ALLOW_HEADERS", "Content-Type,Authorization"),
        cors_allow_methods=os.getenv("CORS_ALLOW_METHODS", "GET,POST,OPTIONS"),
    )
