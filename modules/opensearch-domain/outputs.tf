output "domain_arn" {
  description = "domain 的 ARN。"
  value       = aws_opensearch_domain.this.arn
}

output "domain_name" {
  description = "domain 名稱。"
  value       = aws_opensearch_domain.this.domain_name
}

output "endpoint" {
  description = "domain 的 VPC endpoint（不含 `https://`）。只有 VPC 內與 VPN 連得到。"
  value       = aws_opensearch_domain.this.endpoint
}

output "dashboard_endpoint" {
  description = "OpenSearch Dashboards 的 endpoint（含 `/_dashboards` 路徑，不含 `https://`）。"
  value       = aws_opensearch_domain.this.dashboard_endpoint
}

output "log_group_arns" {
  description = "log group 的 ARN，key 是 log 類型（例如 `AUDIT_LOGS`）。"
  value       = { for t, g in aws_cloudwatch_log_group.this : t => g.arn }
}
