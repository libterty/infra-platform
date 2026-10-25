# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "domain_name" {
  description = "OpenSearch domain 名稱。"
  value       = module.domain.domain_name
}

output "endpoint" {
  description = "domain 的 VPC endpoint（不含 `https://`），只有 VPC 內與 VPN 連得到。"
  value       = module.domain.endpoint
}

output "dashboard_endpoint" {
  description = "OpenSearch Dashboards 的 endpoint（含 `/_dashboards` 路徑，不含 `https://`）。"
  value       = module.domain.dashboard_endpoint
}
