# Operations — cost, reliability, monitoring

## Minimizing cost

- Lambda + HTTP API → scale to zero; 15s timeout, 512MB mem, **reserved concurrency** caps spend.
- DynamoDB on-demand with TTL; store only latest snapshot per user.
- CloudFront `PriceClass_100`; long cache for assets, `index.html` no-store.
- Log retention 14 days.

## Reliability & error handling

- **JWT authorizer** rejects unauth at the edge (no Lambda cold start for bad traffic).
- *(Optional)* **WAFv2** managed rules + IP rate-limit (2k / 5 min / IP).
- Stage throttling (burst 200 / rate 100 rps); Lambda reserved concurrency.
- Coinbase client with timeouts/retries; fall back to **cached** holdings on error.

## Monitoring

- **CloudWatch Metrics/Alarms**:
  - `AWS/Lambda Errors > 0` (5m)
  - `AWS/ApiGateway 5XX > 0` (5m)
  - `Throttles` (Lambda + API), `Duration p95`
- **Access logs** (API): ip, route, status, latency, UA.
- **App logs** (Lambda): cache hit/miss, item count, latency, upstream failures.

## Key metrics

- API: 2xx/4xx/5xx, latency p50/p95/p99, authorizer errors.
- Lambda: invocations, errors, cold starts (via logs), duration p95.
- Cache hit rate for `/holdings`.
- Coinbase upstream: error/timeout counts.
- Auth funnel: Hosted UI success/failure (via CF access logs + Cognito logs).
