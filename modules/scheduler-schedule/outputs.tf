output "schedule_arns" {
  description = "排程名稱 → 排程 ARN。"
  value       = { for name, s in aws_scheduler_schedule.this : name => s.arn }
}
