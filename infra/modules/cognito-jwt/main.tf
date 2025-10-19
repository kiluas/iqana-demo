resource "aws_cognito_user_pool" "users" {
  name                     = "${var.project}-users"
  username_attributes      = ["email"] # login with email
  auto_verified_attributes = ["email"] # verify emails
  password_policy {
    minimum_length    = 8
    require_numbers   = true
    require_symbols   = true
    require_lowercase = true
    require_uppercase = true
  }
}


resource "aws_cognito_user_pool_client" "web" {
  name                                 = "${var.project}-web"
  user_pool_id                         = aws_cognito_user_pool.users.id
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = ["${var.web_origin}/auth/callback"]
  logout_urls                          = ["${var.web_origin}/login"]
  supported_identity_providers         = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "${var.project}-auth-${var.region}"
  user_pool_id = aws_cognito_user_pool.users.id
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = var.api_id
  name             = "${var.project}-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.users.id}"
    audience = [aws_cognito_user_pool_client.web.id]
  }
}


