output "arn" {
  description = "role ARN；所有 inline policy 與 managed policy 都附加好之後才有值。"
  value       = aws_iam_role.this.arn
  depends_on  = [aws_iam_role_policy.this, aws_iam_role_policy_attachment.this]
}

output "name" {
  description = "role 名稱。"
  value       = aws_iam_role.this.name
}

output "id" {
  description = "role ID。"
  value       = aws_iam_role.this.id
}

output "instance_profile_name" {
  description = "instance profile 名稱；沒給 `instance_profile_name` 時為 `null`。"
  value       = one(aws_iam_instance_profile.this[*].name)
}

output "instance_profile_arn" {
  description = "instance profile ARN；沒給 `instance_profile_name` 時為 `null`。"
  value       = one(aws_iam_instance_profile.this[*].arn)
}
