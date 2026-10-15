variable "name_prefix" {
  type        = string
  description = "Profile names are <name_prefix>-<key>."
}

variable "profiles" {
  type = map(object({
    copy_from   = string
    description = optional(string)
  }))
  description = "Application inference profiles keyed by short name. copy_from is the full ARN of a foundation model or a system inference profile; an inference profile must be in the current account. An empty map creates nothing."

  validation {
    condition = alltrue([for k, v in var.profiles :
      length("${var.name_prefix}-${k}") <= 64 &&
      can(regex("^arn:aws[a-z-]*:bedrock:[a-z0-9-]+:([0-9]{12})?:(foundation-model|inference-profile)/[A-Za-z0-9._:-]+$", v.copy_from))
    ])
    error_message = "Names must fit 64 chars; copy_from must be a foundation-model or inference-profile ARN without wildcards."
  }

  # Character rule from the AWS API reference; not verified against a real apply.
  validation {
    condition     = alltrue([for k, v in var.profiles : can(regex("^([0-9a-zA-Z:.][ _-]?)+$", "${var.name_prefix}-${k}"))])
    error_message = "Names may only contain letters, digits, colons and dots, each optionally followed by one space, underscore or hyphen."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every profile; Cost Explorer splits model spend by these tags. Name is set to the profile name."
}
