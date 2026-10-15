variable "name" {
  type        = string
  description = "Full Memory name. Letters, digits and underscores, starting with a letter, at most 48 characters."

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,47}$", var.name))
    error_message = "name must start with a letter and use letters, digits or underscores, at most 48 chars."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "Memory description."
}

variable "event_expiry_days" {
  type        = number
  default     = 90
  nullable    = false
  description = "Days a short-term event is kept, 7-365. Changing it only affects events written afterwards."

  # The aws provider rejects values below 7 at plan time, even though the API documents 3.
  validation {
    condition     = var.event_expiry_days >= 7 && var.event_expiry_days <= 365 && floor(var.event_expiry_days) == var.event_expiry_days
    error_message = "event_expiry_days must be a whole number between 7 and 365."
  }
}

variable "strategies" {
  type = map(object({
    type        = string
    namespaces  = list(string)
    description = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "Built-in long-term memory strategies keyed by strategy name. type is SEMANTIC, SUMMARIZATION or USER_PREFERENCE; namespaces are templates such as /actors/{actorId}/facts. Empty means short-term memory only."

  validation {
    condition     = alltrue([for k in keys(var.strategies) : can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,47}$", k))])
    error_message = "Each strategies key is the strategy name: start with a letter, letters, digits or underscores, at most 48 chars."
  }

  validation {
    condition     = alltrue([for s in values(var.strategies) : contains(["SEMANTIC", "SUMMARIZATION", "USER_PREFERENCE"], s.type)])
    error_message = "strategy type must be SEMANTIC, SUMMARIZATION or USER_PREFERENCE; CUSTOM and self-managed strategies are not supported."
  }

  validation {
    condition     = alltrue([for s in values(var.strategies) : length(s.namespaces) > 0 && alltrue([for n in s.namespaces : startswith(n, "/")])])
    error_message = "Each strategy needs at least one namespace and every namespace must start with /."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed key ARN (key/<uuid>, not an alias) for the Memory. null uses an AWS owned key. The key policy must allow AgentCore to use it."

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<uuid>), not an alias or a wildcard."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the Memory. Name is added automatically; strategies do not take tags."
}
