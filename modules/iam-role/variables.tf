variable "name" {
  type        = string
  description = "Role name."
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.name))
    error_message = "name must be 1-64 chars of letters, digits or +=,.@_-."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "Role description."
}

variable "trust" {
  type = object({
    service_principals = set(string)
    source_account     = optional(string)
    source_arn         = optional(string)
  })
  description = "Trust policy. service_principals are AWS service principals such as ecs-tasks.amazonaws.com; source_account adds an aws:SourceAccount condition when set; source_arn adds an ArnLike aws:SourceArn condition when set (wildcards allowed)."
  validation {
    condition = (
      length(var.trust.service_principals) > 0 &&
      alltrue([for p in var.trust.service_principals : can(regex("^[a-z0-9.-]+\\.amazonaws\\.com$", p))]) &&
      (var.trust.source_account == null ? true : can(regex("^[0-9]{12}$", var.trust.source_account)))
    )
    error_message = "trust needs at least one AWS service principal (no wildcards); source_account must be a 12-digit account ID."
  }
  validation {
    condition     = var.trust.source_arn == null ? true : can(regex("^arn:\\S+$", var.trust.source_arn))
    error_message = "trust.source_arn must be an ARN starting with arn: and contain no whitespace."
  }
}

variable "inline_policies" {
  type        = map(string)
  default     = {}
  description = "Policy name => policy JSON built with jsonencode()."
  validation {
    condition     = alltrue([for p in values(var.inline_policies) : can(jsondecode(p).Statement[0])])
    error_message = "Each inline policy must be a JSON document with a Statement."
  }
  validation {
    condition = alltrue(flatten([
      for p in values(var.inline_policies) : [
        for s in try(jsondecode(p).Statement, []) : [
          for a in flatten([try(s.Action, [])]) : a != "*" && !endswith(a, ":*")
        ] if try(s.Effect, "Allow") == "Allow"
      ]
    ]))
    error_message = "Allow statements must not use * or service:* actions."
  }
  validation {
    condition = alltrue(flatten([
      for p in values(var.inline_policies) : [
        for s in try(jsondecode(p).Statement, []) : !(try(s.Effect, "Allow") == "Allow" && try(s.NotAction, null) != null)
      ]
    ]))
    error_message = "Allow statements must not use NotAction."
  }
  validation {
    condition = alltrue(flatten([
      for p in values(var.inline_policies) : [
        for s in try(jsondecode(p).Statement, []) : !(try(s.Effect, "Allow") == "Allow" && try(s.NotResource, null) != null)
      ]
    ]))
    error_message = "Allow statements must not use NotResource."
  }
}

variable "permissions_boundary" {
  type        = string
  default     = null
  description = "Permissions boundary policy ARN."
}

variable "instance_profile_name" {
  type        = string
  default     = null
  description = "Instance profile name. When set, an instance profile bound to this role is created; null creates none."
  validation {
    condition     = var.instance_profile_name == null ? true : can(regex("^[\\w+=,.@-]{1,128}$", var.instance_profile_name))
    error_message = "instance_profile_name must be 1-128 chars of letters, digits or _+=,.@-."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags merged with Name."
}
