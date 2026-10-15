output "repository_url" {
  description = "Repository URL, without a tag."
  value       = aws_ecr_repository.this.repository_url
}

output "arn" {
  description = "Repository ARN."
  value       = aws_ecr_repository.this.arn
}

output "name" {
  description = "Repository name."
  value       = aws_ecr_repository.this.name
}

output "registry_id" {
  description = "Account ID of the registry that holds the repository."
  value       = aws_ecr_repository.this.registry_id
}
