variable "agent_image_tag" {
  description = "Image tag every Runtime runs. Terraform owns it: change it here and apply, do not update the Runtime with the API."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.agent_image_tag)) && var.agent_image_tag != "latest"
    error_message = "agent_image_tag must be an explicit tag, not latest."
  }
}

variable "model_id" {
  description = "Bedrock model or inference profile id the Runtime converses with. The iam stack allows anthropic models and inference profiles of this account."
  type        = string
}

variable "backend_mode" {
  description = "Which backend the Runtime tools call: fake (built-in test data) or http (the service at backend_url)."
  type        = string
  default     = "fake"

  validation {
    condition     = contains(["fake", "http"], var.backend_mode)
    error_message = "backend_mode must be fake or http."
  }
}

variable "backend_url" {
  description = "Base URL of the backend; required when backend_mode is http."
  type        = string
  default     = ""

  validation {
    condition     = var.backend_mode != "http" || var.backend_url != ""
    error_message = "backend_url is required when backend_mode is http."
  }
}

variable "max_output_length" {
  description = "Upper bound the Runtime puts on the length of a generated answer."
  type        = number
  default     = 2048

  validation {
    condition     = var.max_output_length >= 1 && floor(var.max_output_length) == var.max_output_length
    error_message = "max_output_length must be a positive whole number."
  }
}

variable "memory_event_expiry_days" {
  description = "Days a Memory event is kept, 7-365. It must cover the conversation history the Runtime replays; raising it only affects later events."
  type        = number
  default     = 90
}

variable "guardrail_profile_id" {
  description = "Bedrock cross-region guardrail profile id. No API can check it; only a real ApplyGuardrail call does."
  type        = string
  default     = "apac.guardrail.v1:0"
}

variable "runtime_log_retention_days" {
  description = "Retention of each Runtime's application log group."
  type        = number
  default     = 30
}
