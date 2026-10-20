output "arn" {
  description = "Role ARN. Resolves only after all inline policies are attached."
  value       = aws_iam_role.this.arn
  depends_on  = [aws_iam_role_policy.this]
}

output "name" {
  description = "Role name."
  value       = aws_iam_role.this.name
}

output "id" {
  description = "Role ID."
  value       = aws_iam_role.this.id
}

output "instance_profile_name" {
  description = "Instance profile name, or null when instance_profile_name is not set."
  value       = one(aws_iam_instance_profile.this[*].name)
}

output "instance_profile_arn" {
  description = "Instance profile ARN, or null when instance_profile_name is not set."
  value       = one(aws_iam_instance_profile.this[*].arn)
}
