output "detector_id" {
  description = "detector ID。"
  value       = aws_guardduty_detector.this.id
}

output "detector_arn" {
  description = "detector 的 ARN。"
  value       = aws_guardduty_detector.this.arn
}
