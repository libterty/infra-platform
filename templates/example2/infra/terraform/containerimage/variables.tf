variable "services" {
  description = "Image names other than AgentCore Runtimes: the ECS services and the Lambda functions. This is the single decision point for the list; downstream stacks read it from SSM."
  type        = list(string)

  validation {
    condition     = length(var.services) > 0
    error_message = "Give at least one service."
  }

  validation {
    condition     = alltrue([for s in var.services : can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", s))])
    error_message = "Service names must be kebab-case: lowercase letters and digits separated by single hyphens, starting with a letter."
  }

  validation {
    condition     = length(distinct(var.services)) == length(var.services)
    error_message = "Service names must be unique."
  }
}

variable "agent_runtimes" {
  description = "AgentCore Runtime names. One repository per name; empty creates none."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.agent_runtimes : can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", r))])
    error_message = "Runtime names must be kebab-case: lowercase letters and digits separated by single hyphens, starting with a letter."
  }

  validation {
    # Services and Runtimes share one namespace: the repository name, the key in the published URL map.
    condition     = length(setintersection(var.agent_runtimes, toset(var.services))) == 0
    error_message = "A Runtime name must not be the same as a service name."
  }
}

variable "adopt_existing" {
  description = "true reads repositories that already exist in this account instead of creating them, for an env that shares the account with an earlier env. The repositories must already carry the names <project>-<image>."
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  description = "Image expiry. Untagged images expire after untagged_expire_days; at most keep_count images are kept. Keep enough tags to roll back."
  type = object({
    untagged_expire_days = optional(number, 7)
    keep_count           = optional(number, 50)
  })
  default = {}
}
