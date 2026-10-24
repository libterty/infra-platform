# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "client_vpn" {
  description = "Client VPN 的狀態與連線資訊（JSON）；沒開時是 `{\"enabled\":false}`。"
  value       = local.published_strings["client_vpn"]
}

output "site_to_site" {
  description = "Site-to-Site VPN 的狀態與連線資訊（JSON）；沒開時是 `{\"enabled\":false}`。"
  value       = local.published_strings["site_to_site"]
}
