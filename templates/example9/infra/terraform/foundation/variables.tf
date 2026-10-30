variable "alarm_emails" {
  description = "訂閱告警 topic 的 email。每位收件人要先確認訂閱，才收得到告警。"
  type        = list(string)
  default     = []
}
