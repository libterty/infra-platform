output "arn" {
  description = "connection 的 ARN（`codepipeline` 的 source，以及 pipeline role 的 `codeconnections:UseConnection`）。"
  value       = aws_codeconnections_connection.this.arn
}

output "status" {
  description = "connection 狀態。剛建好是 `PENDING`，要有人在 AWS console 完成授權後才會變成 `AVAILABLE`。"
  value       = aws_codeconnections_connection.this.connection_status
}
