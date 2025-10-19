# iqana_demo/adapters/coinbase_client.py
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import time
from collections.abc import Mapping
from typing import Any, Protocol, TypedDict, cast

import boto3
import httpx
from botocore.exceptions import ClientError

# --- Config (env-tunable) ----------------------------------------------------

SECRET_CACHE_TTL_SECONDS = int(os.getenv("SECRET_CACHE_TTL_SECONDS", "300"))  # 5m
COINBASE_USER_AGENT = os.getenv("CB_USER_AGENT", "iqana-demo/0.2")

# --- Typing helpers ----------------------------------------------------------

class _SecretsManager(Protocol):
    def get_secret_value(self, *, SecretId: str, VersionStage: str | None = None) -> Mapping[str, Any]: ...

class CoinbaseSecret(TypedDict):
    api_key: str
    api_secret_b64: str
    passphrase: str

def _strip_wrapping_quotes(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and ((s[0] == s[-1] == '"') or (s[0] == s[-1] == "'")):
        return s[1:-1]
    return s

def _validate_and_sanitize_secret(obj: Any) -> CoinbaseSecret:
    if not isinstance(obj, dict):
        raise RuntimeError("SecretString must be a JSON object")  # noqa: TRY003
    clean: dict[str, str] = {}
    for key in ("api_key", "api_secret_b64", "passphrase"):
        v = obj.get(key) # type: ignore  # noqa: PGH003
        if not isinstance(v, str) or not v.strip():
            raise RuntimeError(f"Secret missing or invalid '{key}'")
        clean[key] = _strip_wrapping_quotes(v)

    # base64 must decode cleanly
    try:
        base64.b64decode(clean["api_secret_b64"], validate=True)
    except Exception as e:  # noqa: BLE001
        raise RuntimeError("Secret 'api_secret_b64' is not valid base64") from e

    return cast(CoinbaseSecret, clean)

def _ensure_path(path: str) -> str:
    return path if path.startswith("/") else "/" + path

class CoinbaseClient:
    """
    Coinbase Exchange (sandbox) client using legacy Pro-style signing:
      sign = base64(HMAC_SHA256(secret, timestamp + method + path + body))
      Headers: CB-ACCESS-KEY, CB-ACCESS-SIGN, CB-ACCESS-TIMESTAMP, CB-ACCESS-PASSPHRASE
    """

    def __init__(
        self,
        base_url: str,
        secret_name: str,
        secrets_client: _SecretsManager | None = None,
        timeout_seconds: float = 20.0,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.secret_name = secret_name
        self.secrets = secrets_client or boto3.client("secretsmanager") # type: ignore  # noqa: PGH003

        self._secret_cache: CoinbaseSecret | None = None
        self._secret_cache_expiry: float = 0.0

        self._http = httpx.Client(
            base_url=self.base_url,
            timeout=timeout_seconds,
            headers={
                "Accept": "application/json",
                "Content-Type": "application/json",
                "User-Agent": COINBASE_USER_AGENT,
            },
        )

    # --- housekeeping ---------------------------------------------------------

    def close(self) -> None:
        self._http.close()

    def __enter__(self) -> CoinbaseClient:
        return self

    def __exit__(self, exc_type, exc, tb) -> None:  # type: ignore[override]
        self.close()

    # --- secrets (sanitized + cached + AWSCURRENT + auto-refresh) -------------

    def _load_secret_from_aws(self) -> CoinbaseSecret:
        try:
            resp = self.secrets.get_secret_value(SecretId=self.secret_name, VersionStage="AWSCURRENT") # type: ignore  # noqa: PGH003
        except ClientError as e:
            # This already includes KMS decryption behind the scenes; if KMS policy were wrong you'd see AccessDenied here.
            raise RuntimeError(f"Failed to read secret '{self.secret_name}': {e}") from e  # noqa: TRY003

        secret_str = cast(str, resp.get("SecretString") or "{}") # type: ignore  # noqa: PGH003
        parsed = json.loads(secret_str)
        return _validate_and_sanitize_secret(parsed)

    def _get_secret(self, *, force_refresh: bool = False) -> CoinbaseSecret:
        now = time.time()
        if (not force_refresh) and self._secret_cache and now < self._secret_cache_expiry:
            return self._secret_cache

        secret = self._load_secret_from_aws()
        self._secret_cache = secret
        self._secret_cache_expiry = now + SECRET_CACHE_TTL_SECONDS
        return secret

    def _invalidate_secret_cache(self) -> None:
        self._secret_cache = None
        self._secret_cache_expiry = 0.0

    # --- HTTP signing + request ----------------------------------------------

    def _request(
        self,
        method: str,
        path: str,
        json_body: dict[str, Any] | None = None,
        _retried_once: bool = False,
    ) -> Any:
        path = _ensure_path(path)
        sec = self._get_secret()

        body_str = json.dumps(json_body, separators=(",", ":"), ensure_ascii=False) if json_body else ""
        ts = str(int(time.time()))
        prehash = f"{ts}{method.upper()}{path}{body_str}"

        secret_bytes = base64.b64decode(sec["api_secret_b64"])
        sign_b64 = base64.b64encode(
            hmac.new(secret_bytes, prehash.encode("utf-8"), hashlib.sha256).digest()
        ).decode("ascii")

        headers = {
            "CB-ACCESS-KEY": sec["api_key"],
            "CB-ACCESS-SIGN": sign_b64,
            "CB-ACCESS-TIMESTAMP": ts,
            "CB-ACCESS-PASSPHRASE": sec["passphrase"],
        }

        try:
            resp = self._http.request(
                method=method.upper(),
                url=path,
                content=body_str.encode("utf-8") if body_str else None,
                headers=headers,
            )
            resp.raise_for_status()
        except httpx.HTTPStatusError as e:
            # If the key just rotated or was fixed, do a one-time refresh+retry on 401
            if e.response.status_code == 401 and not _retried_once:  # noqa: PLR2004
                self._invalidate_secret_cache()
                # Force immediate reload and retry once
                self._get_secret(force_refresh=True)
                return self._request(method, path, json_body, _retried_once=True)
            # include server payload for debugging (never log secrets)
            raise RuntimeError(f"Coinbase HTTP {e.response.status_code}: {e.response.text}") from e  # noqa: TRY003
        except httpx.HTTPError as e:
            raise RuntimeError(f"Coinbase network error: {e}") from e  # noqa: TRY003

        return resp.json() if resp.text else {}

    # --- API surface ----------------------------------------------------------

    def list_accounts(self) -> list[dict[str, Any]]:
        raw = self._request("GET", "/accounts")

        if isinstance(raw, list):
            return [dict(x) for x in raw if isinstance(x, Mapping)]  # type: ignore # normalize  # noqa: PGH003

        if isinstance(raw, Mapping):
            for key in ("accounts", "data"):
                maybe = raw.get(key) # type: ignore  # noqa: PGH003
                if isinstance(maybe, list):
                    return [dict(x) for x in maybe if isinstance(x, Mapping)] # type: ignore  # noqa: PGH003

        return []
