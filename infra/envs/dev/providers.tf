#############################################
# Required (inject via TF_VAR_* or tfvars)
#############################################
variable "project" {
  type        = string
  description = "Short project slug used in names (e.g., iqana)."
}

variable "region" {
  type        = string
  description = "AWS region (e.g., eu-west-3)."
}

#############################################
# Optional overrides (empty ⇒ derived)
#############################################
variable "table_name" {
  type        = string
  default     = ""
  description = "DynamoDB table name; empty derives to iqana_holdings."
}

variable "role_name" {
  type        = string
  default     = ""
  description = "Lambda execution role; empty derives to iqana-lambda-exec."
}

variable "func_name" {
  type        = string
  default     = ""
  description = "Lambda function name; empty derives to iqana-api."
}

variable "api_name" {
  type        = string
  default     = ""
  description = "API Gateway HTTP API name; empty derives to iqana-http."
}

#############################################
# KMS / Logs
#############################################
variable "kms_alias" {
  type        = string
  default     = "iqana-secrets" # can be 'iqana-secrets' or 'alias/iqana-secrets' (normalized in locals)
  description = "KMS alias to use for Lambda env + CW Logs encryption."
}

variable "log_retention_days" {
  type        = number
  default     = 14
  description = "CloudWatch Logs retention for the function log group."
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "log_retention_days must be between 1 and 3653 (10 years)."
  }
}

#############################################
# Secrets
#############################################


variable "secret_name" {
  type        = string
  default     = "iqana_coinbase_exchange_sandbox"
  description = "Which secret the Lambda reads at runtime (e.g., switch to sandbox by setting this var)."
}

#############################################
# Provider
#############################################

variable "web_origin" { type = string }
variable "enable_public_health" {
  type    = bool
  default = false
}


#############################################
# Provider
#############################################
provider "aws" {
  region = var.region
}
