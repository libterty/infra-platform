output "asg_name" {
  description = "Auto Scaling group name."
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "Auto Scaling group ARN."
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "Launch template ID."
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "Latest launch template version, the one the group launches."
  value       = aws_launch_template.this.latest_version
}
