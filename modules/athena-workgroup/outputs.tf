output "name" {
  description = "workgroup 名稱。"
  value       = aws_athena_workgroup.this.name
}

output "arn" {
  description = "workgroup 的 ARN。"
  value       = aws_athena_workgroup.this.arn
}
