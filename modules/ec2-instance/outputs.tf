output "instance_id" {
  description = "Instance ID, the target for aws ssm start-session."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP address of the instance."
  value       = aws_instance.this.private_ip
}

output "ami_id" {
  description = "ami_id when given, otherwise the latest AMI found when this was last planned. Later AMI releases are ignored by the instance (ignore_changes), so this may not be the AMI in use."
  value       = local.ami_id
}

output "alarm_arns" {
  description = "Alarm ARNs by name; empty when sns_topic_arns is empty."
  value       = tomap({ for a in aws_cloudwatch_metric_alarm.system_status : "status_check_failed_system" => a.arn })
}
