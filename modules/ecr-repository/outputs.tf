output "repository_url" {
  description = "repository URL，不含 tag。"
  value       = aws_ecr_repository.this.repository_url
}

output "arn" {
  description = "repository 的 ARN。"
  value       = aws_ecr_repository.this.arn
}

output "name" {
  description = "repository 名稱。"
  value       = aws_ecr_repository.this.name
}

output "registry_id" {
  description = "repository 所在 registry 的帳號 ID。"
  value       = aws_ecr_repository.this.registry_id
}
