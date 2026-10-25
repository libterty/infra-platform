output "arn" {
  description = "job template 的 ARN；建立 job 時用 `--job-template-arn` 引用。"
  value       = awscc_iot_job_template.this.arn
}

output "job_template_id" {
  description = "job template ID。"
  value       = awscc_iot_job_template.this.job_template_id
}
