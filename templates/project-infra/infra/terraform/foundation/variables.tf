variable "alarm_emails" {
  description = "Email addresses subscribed to the alarm topic. Each recipient must confirm the subscription before alarms arrive."
  type        = list(string)
  default     = []
}
