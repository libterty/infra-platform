# For people running terraform output. bi publishes no SSM keys; nothing reads these.
output "data_source_arns" {
  description = "QuickSight data source 的 ARN。"
  value       = module.quicksight.data_source_arns
}

output "data_set_arns" {
  description = "QuickSight dataset 的 ARN。"
  value       = module.quicksight.data_set_arns
}

output "vpc_connection_arn" {
  description = "VPC connection 的 ARN；沒給 secret 時是 `null`。"
  value       = module.quicksight.vpc_connection_arn
}
