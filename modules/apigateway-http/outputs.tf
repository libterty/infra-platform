output "api_id" {
  description = "HTTP API 的 ID。"
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "預設的 execute-api 網址（`https://<api id>.execute-api.<region>.amazonaws.com`），可以當 CloudFront 的 origin。`disable_execute_api_endpoint` 為 `true` 時這個網址不能用。"
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "execution_arn" {
  description = "API 的 execution ARN，給 `lambda-function` 的 `permissions` 當 `source_arn`（後面接 `/*/*`）。"
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "stage_invoke_url" {
  description = "`$default` stage 的呼叫網址。"
  value       = aws_apigatewayv2_stage.this.invoke_url
}

output "domain_target" {
  description = "custom domain 的 regional 目標 `{ name, zone_id }`，給 `route53-record` 的 alias record；沒有 `custom_domain` 時為 `null`。"
  value = var.custom_domain == null ? null : {
    name    = aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].target_domain_name
    zone_id = aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].hosted_zone_id
  }
}
