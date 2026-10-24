output "vpn_connection_id" {
  description = "VPN 連線的 ID（`vpn-...`）。"
  value       = aws_vpn_connection.this.id
}

output "tunnel_addresses" {
  description = "兩條 tunnel 的 AWS 側公網 IP，順序是 tunnel 1、tunnel 2；設定地端設備時用。"
  value       = [aws_vpn_connection.this.tunnel1_address, aws_vpn_connection.this.tunnel2_address]
}

output "preshared_key_secret_arn" {
  description = "存放 pre-shared key 的 Secrets Manager secret ARN（由 Site-to-Site VPN 服務建立與管理）。要有 `secretsmanager:GetSecretValue` 的身分才讀得到，module 與 state 都不含 key 本身。"
  value       = aws_vpn_connection.this.preshared_key_arn
}

output "vpn_gateway_id" {
  description = "module 建的 virtual private gateway ID；用 `transit_gateway_id` 時是 `null`。"
  value       = one(aws_vpn_gateway.this[*].id)
}

output "log_group_name" {
  description = "tunnel log 的 CloudWatch log group 名稱。"
  value       = aws_cloudwatch_log_group.this.name
}
