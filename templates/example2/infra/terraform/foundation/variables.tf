variable "alarm_emails" {
  description = "Email addresses subscribed to the alarm topic. Each recipient must confirm the subscription before alarms arrive."
  type        = list(string)

  validation {
    # A topic nobody listens to fails silently, so an empty list is a mistake.
    condition     = length(var.alarm_emails) > 0
    error_message = "Give at least one email address."
  }

  validation {
    condition     = alltrue([for e in var.alarm_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Every entry must be an email address."
  }
}
