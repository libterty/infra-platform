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
