output "endpoint_id" {
  description = "Client VPN endpoint 的 ID（`cvpn-endpoint-...`）。"
  value       = aws_ec2_client_vpn_endpoint.this.id
}

output "dns_name" {
  description = "client 連線用的 DNS 名稱；client 設定檔請用這個名稱，不要用 IP（IP 會變）。"
  value       = aws_ec2_client_vpn_endpoint.this.dns_name
}

output "log_group_name" {
  description = "connection log 的 CloudWatch log group 名稱。"
  value       = aws_cloudwatch_log_group.this.name
}
