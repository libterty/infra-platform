output "peering_connection_id" {
  description = "Peering connection ID. Give it to the peer account so it can accept the request."
  value       = aws_vpc_peering_connection.this.id
}
