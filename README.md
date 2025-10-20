# Iqana Demo — Coinbase Holdings (API + Web + AWS)

End-to-end demo that ingests Coinbase balances and serves them via a FastAPI Lambda with a React SPA frontend.

- **Backend:** FastAPI + Mangum on AWS Lambda, JWT-protected by API Gateway.
- **Frontend:** React 19 + Vite, hosted from S3 behind CloudFront.
- **Infra:** Terraform composable modules (`infra/modules/*`) with per-environment stacks (`infra/envs/*`).
- **Auth:** Cognito Hosted UI (PKCE) feeding API Gateway JWT authorizer.
- **Data:** DynamoDB cache, Secrets Manager for Coinbase keys, KMS-encrypted env vars.

Use this runbook to stand up the stack, iterate locally, and deploy updates. Additional documentation lives in:

- [Architecture diagram](docs/assets/arch.png)
- [Backend internals](docs/backend.md)
- [Frontend architecture](docs/frontend.md)
- [Infrastructure deep dive](docs/infra.md)
- [Project structure overview](docs/project_structure.md)
- [Framework decisions](docs/framework_decisions.md)
- [Cost and reliability monitoring](docs/cost_rel_monitoring.md)

---

## 1. Prerequisites
- AWS account with permissions to create IAM roles, Lambda, API Gateway, Cognito, DynamoDB, Secrets Manager, S3, CloudFront, and KMS grants.
- AWS CLI v2 configured with credentials for that account (`aws sts get-caller-identity` should succeed).
- Terraform ≥ 1.6, Node.js ≥ 18, npm, Python 3.12, and `just` (https://github.com/casey/just).
- Optional: `uv`/`pip` for local backend work, and an editor that loads `.env`.

## 2. Environment Configuration
1. Create or edit `.env` and populate the following keys:
   ```dotenv
      ENV=YOUR_ENV # e.g., dev|staging|prod

      TF_VAR_project=YOUR_PROJECT_SLUG
      TF_VAR_region=YOUR_AWS_REGION # e.g., eu-west-3
      TF_VAR_web_origin=https://YOUR_CLOUDFRONT_DOMAIN # e.g., https://exampleabcdef.cloudfront.net
      TF_VAR_secret_name=YOUR_SECRETS_MANAGER_NAME # e.g., coinbase_exchange_sandbox
      TF_VAR_func_name=YOUR_LAMBDA_FUNCTION_NAME
      TF_VAR_api_name=YOUR_API_GATEWAY_NAME
      ZIP_PATH=path/to/your/bundle.zip

      VITE_API_BASE=https://YOUR_API_GATEWAY_BASE_URL
      VITE_COGNITO_DOMAIN=YOUR_COGNITO_DOMAIN # e.g., your-app.auth.eu-west-3.amazoncognito.com
      VITE_COGNITO_CLIENT_ID=YOUR_COGNITO_APP_CLIENT_ID
      VITE_COGNITO_REGION=YOUR_COGNITO_REGION # e.g., eu-west-3
      VITE_COGNITO_REDIRECT_URI=https://YOUR_WEB_ORIGIN/auth/callback
      VITE_COGNITO_LOGOUT_URI=https://YOUR_WEB_ORIGIN/login

   ```
   Adjust values per environment (e.g., different region, project slug, or Cognito domain).
2. Ensure your KMS alias (`TF_VAR_kms_alias`, default `iqana-secrets`) already exists or override the variable before provisioning.
3. Make utility scripts executable once: `chmod +x scripts/**/*.sh`.

## 3. Provision Cloud Infrastructure
All commands run from the repo root (`ENV` defaults to `dev` via `.env`).

```bash
# sanity check required variables
just env-check

# create remote state bucket + DynamoDB lock table (idempotent)
just tf-remote-state

# initialise Terraform backend/provider files and run terraform init
just tf-init

# review the plan (fmt + validate run automatically)
just tf-plan

# apply the stack (Lambda, API GW, Cognito, DynamoDB, S3/CloudFront, VPC, etc.)
just tf-apply
```

Terraform outputs the API endpoint, Lambda name, Cognito domain/client, CloudFront info, and NAT EIP. Store these in `.env`, frontend configs, and secrets managers as needed.

## 4. Deploy Backend Code
Terraform seeds Lambda with a bootstrap stub—push the real package once infra is ready.

```bash
# Build the Lambda zip (scripts/deploy/build_zip_docker.sh handles deps)
just deploy-code
```

`deploy-code` rebuilds the bundle, uploads it via `aws lambda update-function-code`, and publishes the new version.

## 5. Deploy Frontend
Frontend deploys need the S3 bucket and CloudFront distribution outputs (`WEB_BUCKET`, `CLOUDFRONT_ID`).

```bash
export WEB_BUCKET=<s3 bucket name from module.frontend (e.g., iqana-web-dev-eu-west-3)>
export CLOUDFRONT_ID=<cloudfront distribution ID (run: aws cloudfront list-distributions --query "DistributionList.Items[].Id")>

# Build SPA with the Cognito + API env vars from .env
just web-build

# Sync static assets to S3 and invalidate CloudFront
just web-deploy-s3
```

`web-deploy-s3` uploads immutable assets with long cache headers and forces `index.html` to bypass caches. Use the AWS CLI or console to confirm the CloudFront distribution ID before creating invalidations.

## 6. Local Development
- **Backend:** Install deps (`pip install -e .[dev]`), export the same env vars as Lambda, then run `uv run uvicorn iqana_demo.api.app:app --host 0.0.0.0 --port 8000 --reload`. Use dummy secrets or mock AWS clients when iterating locally (see `docs/backend.md`).
- **Frontend:** `cd apps/web && npm ci && npm run dev` starts Vite on http://localhost:5173. Configure Cognito to allow the local redirect URI if you need full auth; otherwise stub responses with a local proxy (see `docs/frontend.md`).
- **Infrastructure changes:** Modify Terraform in `infra/envs/<env>` or `infra/modules/*`, then rerun `just tf-plan` / `just tf-apply`. Use `just tf-format` to keep formatting consistent.

## 7. CI/CD
GitHub Actions (see `.github/workflows/main.yml`) run lint/tests, Terraform plan/apply, and web deploys. Ensure repository secrets provide AWS credentials with matching permissions before enabling live deploys.

## 8. Troubleshooting
- Remote state errors → confirm AWS credentials and that `just tf-remote-state` succeeded.
- Lambda still returns “bootstrap ok” → rerun `just deploy-code`; Terraform ignores the Lambda `filename` to avoid drift.
- 401s after login → verify Cognito domain/client output matches the frontend `.env` (`docs/frontend.md`).
- Coinbase API blocked → whitelist the NAT EIP from Terraform output (`docs/infra.md`).
- Need more detail? Check:
  - Backend internals: `docs/backend.md`
  - Frontend architecture: `docs/frontend.md`
  - Infrastructure deep dive: `docs/infra.md`
