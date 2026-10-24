# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "firehose_names" {
  description = "Firehose delivery stream 名稱，key 為 s3、opensearch。"
  value       = { s3 = module.firehose_s3.name, opensearch = module.firehose_opensearch.name }
}

output "workflow_name" {
  description = "Glue workflow 名稱。"
  value       = module.etl.workflow_name
}

output "job_names" {
  description = "Glue job 名稱。"
  value       = module.etl.job_names
}

output "event_rule_arn" {
  description = "S3 事件的 EventBridge rule ARN。"
  value       = module.etl.event_rule_arn
}
