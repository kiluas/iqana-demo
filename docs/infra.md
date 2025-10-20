# Infrastructure — Terraform (`infra/`)

## Layout & State
- Terraform is split by environment under `infra/envs/<env>`; `dev` is the only committed stack today (`infra/envs/dev/main.tf:1`).
- Remote state lives in an S3 bucket + DynamoDB lock table created by `scripts/tf/remote_state.sh` (`scripts/tf/remote_state.sh:1-43`).
- `scripts/tf/bootstrap.sh` wires the backend config (`backend.hcl`), provider defaults, and stub resources for imports before hand-authored code replaces them (`scripts/tf/bootstrap.sh:1-66`).
- Each environment keeps its own `backend.hcl`, so switching `ENV` in `.env` cleanly targets another workspace.

## Core Stack (dev)
- **Data plane:** DynamoDB cache table, Secrets Manager secret, Lambda function, HTTP API, and CloudWatch logs are all defined in a single root module (`infra/envs/dev/main.tf:18-229`).
- **Security:** Lambda execution role gets least-privilege access to DynamoDB, Secrets Manager (`VersionStage=AWSCURRENT`), and the custom KMS key alias for env vars (`infra/envs/dev/main.tf:80-104`).
- **Bootstrap:** A tiny `archive_file` ZIP keeps Terraform happy before real bundles are deployed; at apply time the Lambda is created with that stub and real code is pushed via `just deploy-code` (`infra/envs/dev/main.tf:144-204`).
- **API Gateway:** `$default` delegates to Lambda, CORS is wide open while iterating, and the `/health` route can be toggled public or JWT-protected (`infra/envs/dev/main.tf:219-387`).
- **Networking:** A dedicated VPC with public/private subnets, a single NAT gateway, and an egress-only security group ensure the Lambda can reach Coinbase while remaining private (`infra/envs/dev/main.tf:271-364`). The NAT’s public IP is output to whitelist upstreams if needed (`infra/envs/dev/main.tf:396-399`).

## Terraform Modules
- `modules/frontend` provisions the static site bucket, CloudFront distribution + OAC, and locks S3 access to CloudFront (`infra/modules/frontend/main.tf:1-78`). Outputs feed deployment commands (`infra/modules/frontend/outputs.tf:1-6`).
- `modules/cognito-jwt` owns the Cognito user pool, SPA client, Hosted UI domain, and API Gateway JWT authorizer (`infra/modules/cognito-jwt/main.tf:1-42`). Its outputs surface client ID and Hosted UI domain for the frontend `.env` (`infra/envs/dev/main.tf:408-415`).
- Environment roots compose these modules so each environment can reuse the same primitives while overriding names or regions.

## Inputs & Configuration

| Variable | Required | Description | Example Source |
| --- | --- | --- | --- |
| `TF_VAR_project` | yes | Short slug used in resource names (`infra/envs/dev/providers.tf:15-34`) | `.env` |
| `TF_VAR_region` | yes | AWS region for all providers (`infra/envs/dev/providers.tf:15-34`) | `.env` |
| `TF_VAR_web_origin` | yes | CloudFront origin fed into Cognito callbacks (`infra/envs/dev/providers.tf:75-79`) | `.env` |
| `TF_VAR_secret_name` | no (defaults) | Swap Secrets Manager ARN suffix when pointing at a different Coinbase key (`infra/envs/dev/providers.tf:65-69`) | `.env` |
| `TF_VAR_kms_alias` | no | Provide a different CMK alias for Lambda/log encryption (`infra/envs/dev/main.tf:10-15`) | `.env` |
| `TF_VAR_log_retention_days` | no | Override Lambda log retention window (`infra/envs/dev/providers.tf:46-55`) | `.env` |
| `TF_VAR_enable_jwt_authorization` | no | Gate `$default` route behind Cognito authorizer (`infra/envs/dev/main.tf:238-246`) | CLI var |
| `TF_VAR_enable_public_health` | no | Leave `/health` public even when JWT is enabled (`infra/envs/dev/main.tf:380-386`) | CLI var |

`Justfile` expects these variables in `.env` alongside `ENV` so commands can reference them consistently (`Justfile:1-71`).

## Standard Workflow
1. `just env-check` confirms `.env` is populated (project, region, function name) (`Justfile:14-24`).
2. `just tf-remote-state` creates or verifies the remote state bucket + lock table (`Justfile:25-27`).
3. `just tf-init` regenerates backend/provider boilerplate for the selected `ENV` and runs `terraform init` (`Justfile:29-32`).
4. `just tf-plan` / `tf-apply` operate in `infra/envs/${ENV}` with fmt + validate guards enabled (`Justfile:39-46`).
5. After infrastructure changes, build and upload the real Lambda bundle via `just deploy-code` or run the combined `just deploy-all` when shipping both code and infra (`Justfile:50-72`).
6. Frontend deployments reuse the outputs (bucket + distribution ID) with `just web-build` / `web-deploy-s3` once `WEB_BUCKET` & `CLOUDFRONT_ID` are exported (`Justfile:73-101`).

## Outputs & Handoffs
- `http_api_endpoint`, `lambda_name`, `cognito_client_id`, and `cognito_domain` bubble up for easy copy/paste into environment files and CloudFront config (`infra/envs/dev/main.tf:401-415`).
- `modules/frontend` exposes `bucket_name` and `cloudfront_domain` for deployment scripts (`infra/modules/frontend/outputs.tf:1-6`).
- Capture Terraform output after `apply` and sync the values into `.env`, `apps/web/.env.production`, or secrets managers to keep environments aligned.

## Troubleshooting
- **Terraform init complains about backend:** Ensure `just tf-remote-state` ran with AWS credentials that can create the bucket/table; check the derived names in `.env`.
- **Lambda still using bootstrap code:** Rebuild + push with `just deploy-code` so Terraform’s ignored `filename` field stays untouched while code updates flow (`infra/envs/dev/main.tf:200-204`).
- **Hosted UI redirect mismatch:** Update `TF_VAR_web_origin` so the Cognito module regenerates callback/logout URLs (`infra/modules/cognito-jwt/main.tf:15-24`).
- **Coinbase access blocked:** Use the `egress_ip_for_coinbase_whitelist` output to register the NAT IP with Coinbase and rerun `tf-apply` if the NAT gateway was recreated (`infra/envs/dev/main.tf:396-399`).
- **Plan churn on CloudFront:** The distribution comment embeds a timestamp, so expect a small diff when you touch the stage; runs with `-refresh=false` can reduce noise if nothing else changed.
