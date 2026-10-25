output "profile_name" {
  description = "signing profile 名稱，開簽章 job 時用。"
  value       = aws_signer_signing_profile.this.name
}

output "profile_arn" {
  description = "signing profile 的 ARN。"
  value       = aws_signer_signing_profile.this.arn
}

output "profile_version_arn" {
  description = "含版本的 signing profile ARN，IAM policy 要鎖定特定版本時用。"
  value       = aws_signer_signing_profile.this.version_arn
}
