variable "services" {
  description = "Service names. This is the single decision point for the service list: network, iam-app and application check their own settings against it."
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

  validation {
    # ecs-service names the service <name_prefix>-<service> and caps it at 26 characters.
    condition     = alltrue([for s in var.services : length("${local.name_prefix}-${s}") <= 26])
    error_message = "<project>-<env>-<service> must be at most 26 characters so it fits the ecs-service name limit."
  }
}

variable "lifecycle_rules" {
  description = "Image expiry. Untagged images expire after untagged_expire_days; at most keep_count images are kept. Tune to the deploy frequency, and keep enough tags to roll back."
  type = object({
    untagged_expire_days = optional(number, 7)
    keep_count           = optional(number, 50)
  })
  default = {}
}

variable "mirrored_images" {
  description = "Names of external images to keep a copy of in a private repository (for example adot-collector), for environments that cannot pull from the internet. One repository <project>-<env>-mirror-<name> is created per name; copy the image into it yourself. Empty creates none."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.mirrored_images : can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", m))])
    error_message = "Mirror names must be kebab-case: lowercase letters and digits separated by single hyphens, starting with a letter."
  }

  validation {
    condition     = length(setintersection(var.mirrored_images, toset(var.services))) == 0
    error_message = "A mirror name must not be the same as a service name."
  }

  validation {
    # A service called mirror-<x> would otherwise get the same repository name as the mirror <x>.
    condition     = length(setintersection(toset([for m in var.mirrored_images : "${local.name_prefix}-mirror-${m}"]), toset([for s in var.services : "${local.name_prefix}-${s}"]))) == 0
    error_message = "A mirror repository name must not be the same as a service repository name."
  }
}

variable "agent_runtimes" {
  description = "AgentCore Runtime names. This is the single decision point for the Runtime list: network and agent check their own Runtime settings against it. One repository <project>-<env>-agent-<name> is created per name. Empty by default, which creates nothing."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.agent_runtimes : can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", r))])
    error_message = "Runtime names must be kebab-case: lowercase letters and digits separated by single hyphens, starting with a letter."
  }

  validation {
    # Runtime names share the SG key, role name and SSM key namespace with services and mirrors.
    condition     = length(setintersection(var.agent_runtimes, setunion(toset(var.services), var.mirrored_images))) == 0
    error_message = "A Runtime name must not be the same as a service or mirror name."
  }

  validation {
    # A service called agent-<x> would otherwise get the same repository name as the Runtime <x>.
    condition     = length(setintersection(toset([for r in var.agent_runtimes : "${local.name_prefix}-agent-${r}"]), toset([for s in var.services : "${local.name_prefix}-${s}"]))) == 0
    error_message = "A Runtime repository name must not be the same as a service repository name."
  }

  validation {
    # The agent stack names the Runtime <project>_<env>_<name>; AgentCore caps Runtime names at 48 characters.
    condition     = alltrue([for r in var.agent_runtimes : length(replace("${local.name_prefix}-${r}", "-", "_")) <= 48])
    error_message = "<project>_<env>_<runtime> must be at most 48 characters so it fits the AgentCore Runtime name limit."
  }
}
