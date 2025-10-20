
### Decisions (frameworks & tools)

**Backend — FastAPI + Mangum (Python 3.12)**

* **FastAPI**: fast dev loop, type-first (Pydantic) models, built-in OpenAPI docs → perfect for a tiny JSON API.
* **Mangum**: paper-thin ASGI adapter so the same app runs locally with Uvicorn and in AWS Lambda behind API Gateway.
* **httpx + Pydantic + boto3**: clean HTTP client with timeouts/retries, strict schemas for responses, and first-party AWS SDK.

**Frontend — React + Vite**

* **React**: ubiquitous, easy to read, componentized UI for a simple holdings table + login flow.
* **Vite**: instant HMR locally, tiny build output; ships a static SPA that CloudFront can cache aggressively.

**Identity — Cognito Hosted UI (PKCE) + API Gateway JWT**

* Hosted UI gives us OAuth/OIDC without building screens or storing passwords.
* API Gateway **JWT authorizer** enforces auth *before* Lambda runs (saves cold starts; simpler backend code).

**Data & Secrets — DynamoDB + Secrets Manager + KMS**

* **DynamoDB (on-demand)** for a cheap, serverless cache with TTL (no capacity planning).
* **Secrets Manager** for Coinbase creds; **KMS** encrypts Lambda env + secret decrypt with Lambda context.

**Infra — Terraform (envs + modules)**

* Declarative, reproducible provisioning; easy to review in PRs.
* **Modules** (e.g., `frontend`, `cognito-jwt`) keep `main.tf` lean and let us toggle features (JWT on/off) via variables.

**Tooling & DevX — uv, Makefile, Just**

* **uv** (by Astral) for fast Python installs/locking; mirrors the local workflow in CI.
* **Makefile** for Python build/test tasks; **Justfile** for cross-stack chores (Terraform, Lambda code deploy, web build/deploy) with environment wiring from `.env`.
* This split keeps Python packaging tidy while giving a single “ops console” for day-to-day commands.

**CI/CD — GitHub Actions**

* Lint (ruff) + tests (pytest/coverage) on every PR; minimal env so tests don’t talk to real AWS.
* Separate jobs for Terraform plan/apply and web build/deploy; easy to gate applies with environment approvals.

**AWS Surface — chosen for cost & simplicity**

* **API Gateway (HTTP API) + Lambda**: scales to zero, minimal moving parts.
* **S3 + CloudFront**: globally cached static web, SPA routing via error mapping.
* **CloudWatch**: access logs + alarms (Lambda Errors, API 5XX) for day-one operability.
* (Optional) **WAFv2**: managed rules + rate-limiting when you want a front-door filter.

**What we deliberately didn’t use (yet)**

* **ECS/EKS**: overkill for a two-endpoint JSON API; Lambda is cheaper and simpler.
* **API Gateway REST**: HTTP API has lower latency/cost and native JWT—fits better here.
