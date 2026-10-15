variable "name" {
  type        = string
  description = "Full repository name. Slash-separated namespaces are allowed."
  validation {
    condition     = length(var.name) >= 2 && length(var.name) <= 256 && can(regex("^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*$", var.name))
    error_message = "name must be a valid ECR repository name (lowercase, digits, . _ - and / separators)."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed key for image encryption. null uses AES256. Changing it on an existing repository replaces the repository and deletes its images."
}

variable "lifecycle_rules" {
  type = object({
    untagged_expire_days = optional(number, 7)
    keep_count           = optional(number, 50)
  })
  default     = {}
  description = "Expire untagged images after untagged_expire_days; keep at most keep_count images."
  validation {
    condition     = var.lifecycle_rules.untagged_expire_days >= 1 && var.lifecycle_rules.keep_count >= 1
    error_message = "untagged_expire_days and keep_count must be at least 1."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags. Name is added automatically."
}
