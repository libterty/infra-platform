output "arn" {
  description = "secret 的 ARN（含 AWS 加的 6 字元後綴）。IAM policy 與 ECS、Lambda 讀 secret 時用這個。"
  value       = aws_secretsmanager_secret.this.arn
}

output "name" {
  description = "secret 的名稱。"
  value       = aws_secretsmanager_secret.this.name
}

output "id" {
  description = "secret 的 ID（等於 ARN）。"
  value       = aws_secretsmanager_secret.this.id
}
