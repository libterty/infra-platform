output "plan_id" {
  description = "backup plan 的 ID。"
  value       = aws_backup_plan.this.id
}

output "plan_arn" {
  description = "backup plan 的 ARN。"
  value       = aws_backup_plan.this.arn
}

output "selection_id" {
  description = "用 tag 選資源的 selection ID。"
  value       = aws_backup_selection.this.id
}
