output "asg_name" {
  description = "Auto Scaling group 名稱。"
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "Auto Scaling group ARN。"
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "launch template ID。"
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "launch template 的最新版本，也就是 ASG 啟動機器用的版本。"
  value       = aws_launch_template.this.latest_version
}
