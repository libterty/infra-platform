output "gateway_id" {
  description = "Gateway id."
  value       = aws_bedrockagentcore_gateway.this.gateway_id
}

output "gateway_arn" {
  description = "Gateway ARN, the resource for bedrock-agentcore:InvokeGateway."
  value       = aws_bedrockagentcore_gateway.this.gateway_arn
}

output "gateway_url" {
  description = "MCP endpoint URL of the gateway."
  value       = aws_bedrockagentcore_gateway.this.gateway_url
}

output "target_ids" {
  description = "Target ids keyed by the targets key."
  value       = tomap({ for k, t in aws_bedrockagentcore_gateway_target.this : k => t.target_id })
}
