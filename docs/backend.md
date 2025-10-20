# Backend — FastAPI on Lambda (`iqana_demo`)

## Stack & Runtime
- FastAPI + Pydantic models served through `Mangum`, allowing the same ASGI app to run locally or inside AWS Lambda.
- Python 3.12, packaged as the `iqana_demo` module; Terraform wires it into API Gateway HTTP APIs.
- Coinbase Exchange sandbox is the only upstream dependency; secrets are pulled from AWS Secrets Manager at runtime.

## Request Flow
1. API Gateway JWT authorizer validates the Cognito ID token before invoking Lambda.
2. Lambda executes `iqana_demo.api.lambda_handler.handler`, which wraps the FastAPI app via `Mangum`.
3. `/health` returns name/version/time for synthetic monitoring.
4. `/holdings` optionally reads a cached snapshot from DynamoDB; otherwise it calls Coinbase, normalises balances, stores the cache, and returns JSON to the caller.

## Module Overview
- `iqana_demo/api/app.py` defines the FastAPI routes, configures CORS, and orchestrates Coinbase + DynamoDB interactions.
- `iqana_demo/adapters/coinbase_client.py` signs requests with Coinbase Pro-style headers using keys stored in Secrets Manager (cached in-memory for 5 minutes).
- `iqana_demo/storage/ddb.py` encapsulates DynamoDB access with typed Boto3 resources, TTL enforcement, and JSON↔Decimal conversion.
- `iqana_demo/core/models.py` shares response payload contracts with the frontend (`HoldingsResponse`, `HealthResponse`, etc.).
- `iqana_demo/core/settings.py` reads environment variables once (`lru_cache`) and raises if the required Terraform-provisioned config is missing.

## Data & Caching
- DynamoDB table (on-demand billing) stores a single item per user: partition key `pk = holdings#<user_id>`.
- Cache payload is stored under `payload`, with `ttl` enforcing expiry; stale entries are ignored and overwritten on refresh.
- Cache TTL defaults to 180 seconds but honours `CACHE_TTL_SECONDS`.
- Coinbase balances ≤ 0 are filtered out; values are rounded to 12 decimal places before returning.

## Authentication & Security
- Authentication: API Gateway HTTP API JWT authorizer, audience/client = Cognito Hosted UI SPA.
- Authorizer ensures the Lambda never executes for invalid tokens, keeping cold starts minimal.
- Secrets: `CB_SECRET_NAME` read via Secrets Manager. Keys are validated (presence, base64 format) and cached; a 401 response triggers an immediate secret refresh.
- IAM policies (via Terraform) restrict Lambda to `GetSecretValue` on the Coinbase secret, `GetItem`/`PutItem` for the holdings table, and `Decrypt` on the scoped KMS key.

## Environment Variables

| Variable | Required | Purpose | Example |
| --- | --- | --- | --- |
| `APP_NAME` | optional | Appears in `/health` | `Iqana Demo` |
| `APP_VERSION` | optional | Reported via `/health` | `0.1.0` |
| `DEFAULT_USER_ID` | required | Partition key suffix in DynamoDB | `demo-user` |
| `DDB_TABLE` | required | DynamoDB table name for cache | `iqana_holdings` |
| `CB_BASE_URL` | required | Coinbase API base URL | `https://api-public.sandbox.exchange.coinbase.com` |
| `CB_SECRET_NAME` | required | Secrets Manager name for API keys | `iqana_coinbase_exchange_sandbox` |
| `CACHE_TTL_SECONDS` | optional | Cache freshness window | `180` |
| `CORS_ALLOW_ORIGIN` | optional | Overrides default origin in CORS middleware | `ex-value` |
| `CORS_ALLOW_HEADERS` | optional | CORS header allow-list | `Content-Type,Authorization` |
| `CORS_ALLOW_METHODS` | optional | CORS method allow-list | `GET,POST,OPTIONS` |
| `SECRET_CACHE_TTL_SECONDS` | optional | Coinbase secret cache per Lambda container | `300` |

Terraform sets these during deploy; for local work create a `.env` as shown in README and load it before starting services.

## Local Development
```bash
pip install -e .[dev]   # include httpx, fastapi, mangum, boto3, mypy stubs
uv run uvicorn iqana_demo.api.app:app --host 0.0.0.0 --port 8000 --reload
```

- Stub environment variables or enable `DEMO_MODE` when adding new tests to avoid real AWS calls.
- Use the FastAPI docs at `http://localhost:8000/docs` for manual requests. Supply `Authorization: Bearer <JWT>` headers to mimic production.
- `tests/test_health.py` covers the health endpoint; add more tests near `tests/` to validate new business logic (mock boto3/httpx as needed).

## Deployment & Operations
- `just tf-apply` provisions Cognito, API Gateway, Lambda, DynamoDB, Secrets, and supporting infra.
- `just deploy-code` rebuilds the Lambda bundle and pushes code updates without touching infrastructure.
- CloudWatch Logs store app output; structured errors (cache miss, Coinbase failure) are logged via raised `RuntimeError`s which appear in Lambda logs.
- Alarms (see Terraform) watch Lambda errors and API Gateway 5XX responses; investigate repeated cache misses or Coinbase timeouts.

## Troubleshooting
- **401 from Coinbase:** AWS secret might be rotated; the client auto-refreshes once, but confirm the new secret fields are correct.
- **Cache not invalidating:** Check that `CACHE_TTL_SECONDS` is large enough and that the Lambda has `dynamodb:PutItem` permissions.
- **Cold-start spikes:** If auth failures trigger Lambda, verify the API Gateway JWT configuration still matches the Cognito client.
- **Local testing errors (`NoRegionError`):** Export `AWS_REGION`/`AWS_DEFAULT_REGION` or set `AWS_EC2_METADATA_DISABLED=true` during tests.
