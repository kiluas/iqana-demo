from __future__ import annotations

from pydantic import BaseModel, Field


class HoldingItem(BaseModel):
    currency: str = Field(..., examples=["BTC"])
    balance: float = Field(..., ge=0)


class HoldingsPayload(BaseModel):
    source: str = "coinbase_exchange_sandbox"
    fetched_at: int
    count: int
    items: list[HoldingItem]


class HoldingsResponse(BaseModel):
    cached: bool
    source: str
    fetched_at: int
    count: int
    items: list[HoldingItem]


class HealthResponse(BaseModel):
    ok: bool = True
    name: str
    version: str
    time: int
