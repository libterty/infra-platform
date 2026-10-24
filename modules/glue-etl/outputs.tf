output "crawler_names" {
  description = "crawler 名稱，由小到大排序。"
  value       = sort(keys(aws_glue_crawler.this))
}

output "job_names" {
  description = "job 名稱，由小到大排序。"
  value       = sort(keys(aws_glue_job.this))
}

output "workflow_name" {
  description = "workflow 名稱；沒建 workflow 時是 `null`。"
  value       = one(aws_glue_workflow.this[*].name)
}

output "workflow_arn" {
  description = "workflow 的 ARN；沒建 workflow 時是 `null`。EventBridge 的 target 與 role 的 `glue:notifyEvent` 都用這個 ARN。"
  value       = one(aws_glue_workflow.this[*].arn)
}

output "event_rule_arn" {
  description = "S3 事件的 EventBridge rule ARN；沒給 `event_trigger` 時是 `null`。給 EventBridge role 的 trust policy 當 `aws:SourceArn` 用。"
  value       = one(aws_cloudwatch_event_rule.this[*].arn)
}

output "security_configuration_name" {
  description = "job 與 crawler 共用的 security configuration 名稱。"
  value       = aws_glue_security_configuration.this.name
}
