#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-eu-west-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-tf-state-${ACCOUNT_ID}-${REGION}}"
DDB_TABLE="${DDB_TABLE:-tf-state-lock}"

echo "Region: $REGION"
echo "Account: $ACCOUNT_ID"
echo "State bucket: $TF_STATE_BUCKET"
echo "Lock table: $DDB_TABLE"

# Create S3 bucket (handle us-east-1 quirk)
if ! aws s3api head-bucket --bucket "$TF_STATE_BUCKET" >/dev/null 2>&1; then
  echo "Creating S3 bucket for Terraform state..."
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$TF_STATE_BUCKET"
  else
    aws s3api create-bucket \
      --bucket "$TF_STATE_BUCKET" \
      --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
fi

echo "Enabling bucket hardening & versioning..."
aws s3api put-bucket-versioning --bucket "$TF_STATE_BUCKET" --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$TF_STATE_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB lock table if missing
if ! aws dynamodb describe-table --region "$REGION" --table-name "$DDB_TABLE" >/dev/null 2>&1; then
  echo "Creating DynamoDB lock table..."
  aws dynamodb create-table \
    --region "$REGION" \
    --table-name "$DDB_TABLE" \
    --billing-mode PAY_PER_REQUEST \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH
fi

echo "Remote state prerequisites ready."
