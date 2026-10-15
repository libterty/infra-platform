output "arn" {
  description = "Role ARN. Resolves only after all inline policies are attached."
  value       = aws_iam_role.this.arn
  depends_on  = [aws_iam_role_policy.this]
}

output "name" {
  description = "Role name."
  value       = aws_iam_role.this.name
}

output "id" {
  description = "Role ID."
  value       = aws_iam_role.this.id
}
