variable "service_alarms_enabled" {
  description = "Create the alarms and the dashboard of the api and the worker."
  type        = bool
  default     = false
}

variable "stream_alarms_enabled" {
  description = "Create the alarms on the stream backlog and on a missing consumer."
  type        = bool
  default     = false
}

variable "log_alarms_enabled" {
  description = "Create the log metric filters and alarms on persistence events and on rate limit fail-open."
  type        = bool
  default     = false
}

variable "tracing_enabled" {
  description = "Deliver the traces of the AgentCore Runtimes and Memory to X-Ray."
  type        = bool
  default     = false
}
