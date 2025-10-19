from __future__ import annotations

import time
from typing import Any

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

from iqana_demo.adapters.coinbase_client import CoinbaseClient
from iqana_demo.core.models import HealthResponse, HoldingItem, HoldingsPayload, HoldingsResponse
from iqana_demo.core.settings import Settings, get_settings
from iqana_demo.storage.ddb import HoldingsCache

settings: Settings = get_settings()
app = FastAPI(title=settings.app_name, version=settings.app_version)

# Dev-friendly CORS (tighten later)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://d3t98z7xoex9ak.cloudfront.net"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

# Services (singletons per Lambda container)
_coinbase = CoinbaseClient(base_url=settings.cb_base_url, secret_name=settings.secret_name)
_cache = HoldingsCache(table_name=settings.ddb_table)

def _now_epoch() -> int:
    return int(time.time())

@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(name=settings.app_name, version=settings.app_version, time=_now_epoch())

@app.get("/holdings", response_model=HoldingsResponse)
def holdings(refresh: bool = Query(False, description="Force refresh from Coinbase")) -> HoldingsResponse:
    user_id = settings.default_user_id

    if not refresh:
        cached: dict[str, Any] | None = _cache.read(user_id)
        if cached:
            return HoldingsResponse(cached=True, **cached)

    # Fetch fresh
    accounts: list[dict[str, Any]] = _coinbase.list_accounts()
    items: list[HoldingItem] = []
    for acc in accounts:
        currency_raw = acc.get("currency") or acc.get("profile_id") or "UNKNOWN"
        currency = str(currency_raw)
        # balance fields vary across responses
        balance_field = acc.get("balance")
        raw_balance = ( # type: ignore  # noqa: PGH003
            balance_field.get("amount") if isinstance(balance_field, dict) else balance_field # type: ignore  # noqa: PGH003
        )
        if raw_balance is None:
            raw_balance = acc.get("available") or acc.get("amount")
        if raw_balance is None:
            raw_balance = "0"
        try:
            balance = float(raw_balance) # type: ignore  # noqa: PGH003
        except (TypeError, ValueError):
            balance = 0.0
        if balance <= 0:
            continue
        items.append(HoldingItem(currency=currency, balance=round(balance, 12)))

    payload: dict[str, Any] = HoldingsPayload(
        source="coinbase_exchange_sandbox",
        fetched_at=_now_epoch(),
        count=len(items),
        items=items,
    ).model_dump()

    _cache.write(user_id, payload, ttl_seconds=settings.cache_ttl_seconds)
    return HoldingsResponse(cached=False, **payload)
