output "budget_arns" {
  description = "預算名稱對 ARN 的 map。"
  value       = { for k, b in aws_budgets_budget.this : k => b.arn }
}
