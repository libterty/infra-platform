output "instance_id" {
  description = "instance ID，`aws ssm start-session` 的 target。"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "instance 的私有 IP。"
  value       = aws_instance.this.private_ip
}

output "ami_id" {
  description = "有給 `ami_id` 時就是它，否則是最近一次 plan 時查到的最新 AMI。因為 `ignore_changes = [ami]`，不一定是這台實際在用的。"
  value       = local.ami_id
}

output "alarm_arns" {
  description = "告警名稱對應 ARN 的 map，key 是 `status_check_failed_system`；`sns_topic_arns` 為空時是空 map。"
  value       = tomap({ for a in aws_cloudwatch_metric_alarm.system_status : "status_check_failed_system" => a.arn })
}
