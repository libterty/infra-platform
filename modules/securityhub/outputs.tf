output "account_id" {
  description = "啟用 Security Hub 的帳號 ID。"
  value       = aws_securityhub_account.this.id
}

output "standards_subscription_arns" {
  description = "標準短名 → 訂閱的 ARN。"
  value       = { for k, s in aws_securityhub_standards_subscription.this : k => s.arn }
}
