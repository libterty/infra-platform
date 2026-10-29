variable "trail_log_retention_days" {
  description = "CloudTrail 送到 CloudWatch Logs 的保存天數（dev 90、sit 365）。只影響告警用的 log group；稽核證據在 trail bucket，保存 365 天。"
  type        = number
}
