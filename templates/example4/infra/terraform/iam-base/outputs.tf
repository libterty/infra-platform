# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "role_arns" {
  description = "Role ARN，key 為 firehose、glue_crawler、glue_job、glue_events、redshift、quicksight_vpc。"
  value       = { for k, m in module.role : k => m.arn }
}
