output "peering_connection_id" {
  description = "peering 連線 ID，交給對端帳號接受請求。"
  value       = aws_vpc_peering_connection.this.id
}
