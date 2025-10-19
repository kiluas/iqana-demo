#!/usr/bin/env bash
set -euo pipefail
PROJECT="${1:?project}"
REGION="${2:?region}"
ENV="${3:?env}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TF_DIR="infra/envs/${ENV}"
BUCKET="${TF_STATE_BUCKET:-tf-state-${ACCOUNT_ID}-${REGION}}"
TABLE="${DDB_TABLE:-tf-state-lock}"

mkdir -p "$TF_DIR"

cat > "${TF_DIR}/versions.tf" <<'HCL'
terraform {
  required_version = ">= 1.6.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } }
  backend "s3" {}
}
HCL

cat > "${TF_DIR}/providers.tf" <<HCL
variable "region" {
  type    = string
  default = "${REGION}"
}

variable "project" {
  type    = string
  default = "${PROJECT}"
}

provider "aws" {
  region = var.region
}
HCL


cat > "${TF_DIR}/backend.hcl" <<HCL
bucket         = "${BUCKET}"
key            = "${PROJECT}/${ENV}/terraform.tfstate"
region         = "${REGION}"
dynamodb_table = "${TABLE}"
encrypt        = true
HCL

# Stubs for import (we'll replace with full blocks)
cat > "${TF_DIR}/main.tf" <<'HCL'
locals {
  table_name = "${var.project}_holdings"
  role_name  = "${var.project}-lambda-exec"
  func_name  = "${var.project}-api"
  api_name   = "${var.project}-http"
}
resource "aws_dynamodb_table" "holdings" {}
resource "aws_secretsmanager_secret" "coinbase" {}
resource "aws_iam_role" "lambda_exec" {}
resource "aws_lambda_function" "api" {}
resource "aws_apigatewayv2_api" "http" {}
resource "aws_apigatewayv2_integration" "lambda" {}
resource "aws_apigatewayv2_route" "default" {}
resource "aws_apigatewayv2_stage" "default" {}
HCL

terraform -chdir="${TF_DIR}" init -backend-config=backend.hcl
echo "Bootstrapped Terraform in ${TF_DIR}"
