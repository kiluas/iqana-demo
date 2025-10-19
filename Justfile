# Load .env automatically
set dotenv-load := true
set dotenv-filename := ".env"
set shell := ["bash","-eu","-o","pipefail","-c"]

# ─────────────────────────────────────────────────────────────────────────────
# Helpers — we read everything from .env to avoid drift.
# Expected .env keys:
#   ENV, TF_VAR_project, TF_VAR_region, TF_VAR_func_name, TF_VAR_api_name, ZIP_PATH
# Optional:
#   TF_BACKEND_BUCKET, TF_LOCK_TABLE
# ─────────────────────────────────────────────────────────────────────────────

# Print key env so you see what's being used
env-check:
    echo "ENV                = ${ENV:-dev}"
    echo "PROJECT (TF_VAR_)  = ${TF_VAR_project:?missing in .env}"
    echo "REGION   (TF_VAR_) = ${TF_VAR_region:?missing in .env}"
    echo "FUNC_NAME(TF_VAR_) = ${TF_VAR_func_name:-${TF_VAR_project}-api}"
    echo "API_NAME (TF_VAR_) = ${TF_VAR_api_name:-${TF_VAR_project}-http}"
    echo "ZIP_PATH           = ${ZIP_PATH:-bundle.zip}"
    echo "TF_BACKEND_BUCKET  = ${TF_BACKEND_BUCKET:-<auto>}"
    echo "TF_LOCK_TABLE      = ${TF_LOCK_TABLE:-<auto>}"

# 0) one-time: create or ensure backend S3/DDB exist
tf-remote-state:
    scripts/tf/remote_state.sh

# 1) init/reconfigure terraform backend for this env
tf-init:
    scripts/tf/bootstrap.sh

# 2) inspect helpful resource IDs (safe to run anytime)
tf-discover:
    scripts/tf/discover.sh
tf-format:
    terraform -chdir=infra fmt -recursive
# 3) plan/apply/destroy as needed
tf-plan:
    terraform -chdir=infra/envs/${ENV:-dev} fmt -check
    terraform -chdir=infra/envs/${ENV:-dev} validate
    terraform -chdir=infra/envs/${ENV:-dev} plan

tf-apply:
    terraform -chdir=infra/envs/${ENV:-dev} apply -auto-approve

tf-destroy:
    terraform -chdir=infra/envs/${ENV:-dev} destroy -auto-approve

# 4) Build a Lambda zip (pure code deploy; no TF)
zip:
    scripts/deploy/build_zip.sh

# 5) Fast code-only deploy to Lambda using the zip
deploy-code:
    scripts/deploy/build_zip_docker.sh

    aws --region "${TF_VAR_region:?}" lambda update-function-code \
      --function-name "${TF_VAR_func_name:-${TF_VAR_project}-api}" \
      --zip-file "fileb://${ZIP_PATH:-bundle.zip}" \
      --publish
    echo "Deployed code to Lambda: ${TF_VAR_func_name:-${TF_VAR_project}-api}"

# 6) Convenience — print the HTTP API URL
api-url:
    aws --region "${TF_VAR_region:?}" apigatewayv2 get-apis \
      --query "Items[?Name=='${TF_VAR_api_name:-${TF_VAR_project}-http}'].ApiEndpoint | [0]" \
      --output text

# One-shot: apply infra then push code
deploy-all: tf-apply deploy-code api-url

web-build:
  @echo "Building web with:"
  @echo "  VITE_API_BASE=${VITE_API_BASE}"
  @echo "  VITE_COGNITO_DOMAIN=${VITE_COGNITO_DOMAIN}"
  @echo "  VITE_COGNITO_CLIENT_ID=${VITE_COGNITO_CLIENT_ID}"
  @echo "  VITE_COGNITO_REGION=${VITE_COGNITO_REGION}"
  @echo "  VITE_COGNITO_REDIRECT_URI=${VITE_COGNITO_REDIRECT_URI}"
  @echo "  VITE_COGNITO_LOGOUT_URI=${VITE_COGNITO_LOGOUT_URI}"
  cd apps/web && \
    VITE_API_BASE="${VITE_API_BASE:?set VITE_API_BASE in .env}" \
    VITE_COGNITO_DOMAIN="${VITE_COGNITO_DOMAIN:?set VITE_COGNITO_DOMAIN in .env}" \
    VITE_COGNITO_CLIENT_ID="${VITE_COGNITO_CLIENT_ID:?set VITE_COGNITO_CLIENT_ID in .env}" \
    VITE_COGNITO_REGION="${VITE_COGNITO_REGION:?set VITE_COGNITO_REGION in .env}" \
    VITE_COGNITO_REDIRECT_URI="${VITE_COGNITO_REDIRECT_URI:?set VITE_COGNITO_REDIRECT_URI in .env}" \
    VITE_COGNITO_LOGOUT_URI="${VITE_COGNITO_LOGOUT_URI:?set VITE_COGNITO_LOGOUT_URI in .env}" \
    npm ci && npm run build



web-deploy-s3:
  just web-build
  aws s3 sync apps/web/dist "s3://${WEB_BUCKET:?}" \
    --cache-control 'public,max-age=31536000,immutable' \
    --exclude index.html
  aws s3 cp apps/web/dist/index.html "s3://${WEB_BUCKET:?}/index.html" \
    --cache-control 'no-store'
  aws cloudfront create-invalidation \
    --distribution-id "${CLOUDFRONT_ID:?}" \
    --paths '/*'

list-fe-address:
  aws cloudfront list-distributions \
  --query "DistributionList.Items[].{ID:Id,DOMAIN:DomainName}" \
  --output tableaws_apigatewayv2_route
