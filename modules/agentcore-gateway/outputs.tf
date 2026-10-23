output "gateway_id" {
  description = "Gateway id。"
  value       = aws_bedrockagentcore_gateway.this.gateway_id
}

output "gateway_arn" {
  description = "Gateway ARN，`bedrock-agentcore:InvokeGateway` 的 resource。"
  value       = aws_bedrockagentcore_gateway.this.gateway_arn
}

output "gateway_url" {
  description = "Gateway 的 MCP 端點 URL。"
  value       = aws_bedrockagentcore_gateway.this.gateway_url
}

output "target_ids" {
  description = "key 同 `targets` 的 map，值是 target id。"
  value       = tomap({ for k, t in aws_bedrockagentcore_gateway_target.this : k => t.target_id })
}
