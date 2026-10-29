# For people running terraform output. No other stack reads this stack, so it publishes nothing to SSM.
output "budget_arns" {
  description = "預算名稱對 ARN 的 map。"
  value       = module.budgets.budget_arns
}
