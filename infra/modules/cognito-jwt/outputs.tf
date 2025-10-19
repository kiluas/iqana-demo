output "authorizer_id" { value = aws_apigatewayv2_authorizer.jwt.id }
output "user_pool_id" { value = aws_cognito_user_pool.users.id }
output "client_id" { value = aws_cognito_user_pool_client.web.id }
output "domain_prefix" { value = aws_cognito_user_pool_domain.domain.domain }
