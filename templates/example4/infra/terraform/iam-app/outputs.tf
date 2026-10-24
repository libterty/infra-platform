# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "role_quicksight_athena_arn" {
  description = "quicksight-athena role 的 ARN。"
  value       = module.quicksight_athena_role.arn
}

output "firehose_policy_names" {
  description = "附加在 iam-base 建立的 firehose role 上的 inline policy 名稱。"
  value       = module.firehose_policy.policy_names
}
