locals {
  project = var.project
  region  = var.region

  table_name = var.table_name != "" ? var.table_name : "${var.project}_holdings"
  role_name  = var.role_name != "" ? var.role_name : "${var.project}-lambda-exec"
  func_name  = var.func_name != "" ? var.func_name : "${var.project}-api"
  api_name   = var.api_name != "" ? var.api_name : "${var.project}-http"

  # allow 'iqana-secrets' or 'alias/iqana-secrets'
  kms_alias_normalized = startswith(var.kms_alias, "alias/") ? var.kms_alias : "alias/${var.kms_alias}"
}

data "aws_kms_alias" "secrets" {
  name = local.kms_alias_normalized
}

# Already-existing resources you’re importing
resource "aws_dynamodb_table" "holdings" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  attribute {
    name = "pk"
    type = "S"
  }
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
  tags = { Project = local.project }
}


resource "aws_secretsmanager_secret" "secret" {
  name = var.secret_name
  tags = { Project = local.project }
  lifecycle {
    ignore_changes = [kms_key_id]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = local.role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Project = local.project }
}

# Attach AWS managed logging helper
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Single baseline policy (includes KMS decrypt); replaces the old 'kms_decrypt' inline policy
data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "lambda_least_priv" {
  name = "iqana-least-priv"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # DynamoDB: only your table
      {
        Sid      = "DynamoRW",
        Effect   = "Allow",
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem"],
        Resource = "arn:aws:dynamodb:${local.region}:${data.aws_caller_identity.current.account_id}:table/${local.table_name}"
      },

      # Secrets: only the secret your Lambda reads (AWSCURRENT)
      {
        Sid      = "SecretReadCurrent",
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = "arn:aws:secretsmanager:${local.region}:${data.aws_caller_identity.current.account_id}:secret:${var.secret_name}*",
        Condition = {
          StringEquals = { "secretsmanager:VersionStage" = "AWSCURRENT" }
        }
      },

      # KMS: decrypt Lambda env vars (uses Lambda encryption context)
      {
        Sid      = "KMSDecryptLambdaEnv",
        Effect   = "Allow",
        Action   = ["kms:Decrypt"],
        Resource = data.aws_kms_alias.secrets.target_key_arn,
        Condition = {
          StringEquals = { "kms:EncryptionContext:LambdaFunctionName" = local.func_name }
        }
      },

    ]
  })
}

# KMS-encrypted log group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.func_name}"
  retention_in_days = var.log_retention_days
  tags              = { Project = local.project }
}

resource "aws_cloudwatch_log_group" "apigw_access" {
  name              = "/aws/apigw/${local.api_name}"
  retention_in_days = 14
  tags              = { Project = local.project }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
  tags        = { Project = local.project }
  description = "redeploy ${timestamp()}"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw_access.arn
    format = jsonencode({
      requestId = "$context.requestId"
      ip        = "$context.identity.sourceIp"
      routeKey  = "$context.routeKey"
      status    = "$context.status"
      latency   = "$context.responseLatency"
      userAgent = "$context.identity.userAgent"
    })
  }

  default_route_settings {
    throttling_burst_limit = 200
    throttling_rate_limit  = 100
  }
}

# Tiny bootstrap zip so TF can create the function
data "archive_file" "bootstrap_zip" {
  type        = "zip"
  output_path = "${path.module}/bootstrap.zip"

  # package markers
  source {
    filename = "iqana_demo/__init__.py"
    content  = ""
  }
  source {
    filename = "iqana_demo/api/__init__.py"
    content  = ""
  }

  # minimal stub at the SAME path as your real handler
  # (so Terraform can create the function even before you deploy real code)
  source {
    filename = "iqana_demo/api/lambda_handler.py"
    content  = <<PY
def handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": "bootstrap ok"
    }
PY
  }
}


resource "aws_lambda_function" "api" {
  function_name = local.func_name
  role          = aws_iam_role.lambda_exec.arn
  runtime       = "python3.12"
  handler       = "iqana_demo.api.lambda_handler.handler"
  filename      = data.archive_file.bootstrap_zip.output_path

  timeout     = 15
  memory_size = 512
  tracing_config { mode = "Active" }

  # Encrypt env vars with your CMK
  kms_key_arn = data.aws_kms_alias.secrets.target_key_arn

  environment {
    variables = {
      DDB_TABLE         = aws_dynamodb_table.holdings.name
      CB_SECRET_NAME    = var.secret_name
      CACHE_TTL_SECONDS = "180"
      DEMO_MODE         = "true"
      APP_NAME          = "Iqana Demo"
      APP_VERSION       = "0.1.0"
      DEFAULT_USER_ID   = "demo-user"
    }
  }

  lifecycle {
    # keep your fast CLI code deploys
    ignore_changes = [filename, s3_bucket, s3_key, image_uri, source_code_hash]
  }

  vpc_config {
    subnet_ids         = [for s in aws_subnet.private : s.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy_attachment.lambda_logs
  ]

  tags = { Project = local.project }
}

resource "aws_apigatewayv2_api" "http" {
  name          = local.api_name
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]          # or ["*"] just to test
    allow_methods = ["GET","POST","OPTIONS"]  # OPTIONS is critical
    allow_headers = ["*"]                     # loosen to debug, tighten later
    max_age       = 86400
  }
  tags = { Project = local.project }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"

  # Toggle JWT on/off from TF_VAR_enable_jwt_authorization
  authorization_type = var.enable_jwt_authorization ? "JWT" : "NONE"
  authorizer_id      = var.enable_jwt_authorization ? module.cognito_jwt.authorizer_id : null
}

resource "aws_apigatewayv2_route" "options_all" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "OPTIONS /{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "NONE"   # <-- critical: never challenge preflight
}


resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGWInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${local.region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.http.id}/*/*"
}

module "frontend" {
  source  = "../../modules/frontend"
  project = var.project
  region  = var.region
  env     = "dev"
}

# ---------- Networking ----------
data "aws_availability_zones" "available" { state = "available" }

resource "aws_vpc" "main" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${local.project}-vpc", Project = local.project }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.project}-igw", Project = local.project }
}

# Two public subnets
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index) # 10.10.0.0/24, 10.10.1.0/24
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.project}-public-${count.index}", Project = local.project }
}

# Two private subnets
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, 10 + count.index) # 10.10.10.0/24, 10.10.11.0/24
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "${local.project}-private-${count.index}", Project = local.project }
}

# Public route table -> IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${local.project}-public-rt", Project = local.project }
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT (single AZ for dev) + EIP
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.project}-nat-eip", Project = local.project }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${local.project}-nat", Project = local.project }
  depends_on    = [aws_internet_gateway.igw]
}

# Private route table -> NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${local.project}-private-rt", Project = local.project }
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security group for Lambda (egress only)
resource "aws_security_group" "lambda" {
  name        = "${local.project}-lambda-sg"
  description = "Egress-only for Lambda"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.project}-lambda-sg", Project = local.project }
}

variable "enable_jwt_authorization" {
  type    = bool
  default = false
}

module "cognito_jwt" {
  source     = "../../modules/cognito-jwt"
  project    = local.project
  region     = local.region
  api_id     = aws_apigatewayv2_api.http.id
  web_origin = var.web_origin
}


resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"

  authorization_type = var.enable_public_health ? "NONE" : (var.enable_jwt_authorization ? "JWT" : "NONE")
  authorizer_id      = var.enable_public_health ? null : (var.enable_jwt_authorization ? module.cognito_jwt.authorizer_id : null)
}


# ---------- IAM: allow Lambda ENI/VPC access ----------
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# ---------- Output the public egress IP to whitelist ----------
output "egress_ip_for_coinbase_whitelist" {
  value = aws_eip.nat.public_ip
}

output "http_api_endpoint" {
  value = aws_apigatewayv2_api.http.api_endpoint
}
output "lambda_name" {
  value = aws_lambda_function.api.function_name
}

# Bubble up Cognito outputs from the module so apply/outputs show them
output "cognito_client_id" {
  value = module.cognito_jwt.client_id
}

output "cognito_domain" {
  # Hosted UI base domain
  value = "${module.cognito_jwt.domain_prefix}.auth.${local.region}.amazoncognito.com"
}
