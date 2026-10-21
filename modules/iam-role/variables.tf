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
    service_principals = optional(set(string), [])
    tag_session        = optional(bool, false)
    source_account     = optional(string)
    source_arn         = optional(string)
    federated = optional(object({
      oidc_provider_arn = string
      subject           = string
    }))
  })
  description = "Trust policy. Give either service_principals (AWS service principals such as ecs-tasks.amazonaws.com or pods.eks.amazonaws.com) or federated (IRSA: oidc_provider_arn plus a single service account subject system:serviceaccount:<namespace>:<serviceaccount>), not both. tag_session adds sts:TagSession (service principals only; Pod Identity and EKS Auto Mode need it). source_account adds an aws:SourceAccount condition when set; source_arn adds an ArnLike aws:SourceArn condition when set (wildcards allowed); both apply to service principals only."
  validation {
    condition = (
      (length(var.trust.service_principals) > 0) != (var.trust.federated != null) &&
      alltrue([for p in var.trust.service_principals : can(regex("^[a-z0-9.-]+\\.amazonaws\\.com$", p))]) &&
      (var.trust.source_account == null ? true : can(regex("^[0-9]{12}$", var.trust.source_account)))
    )
    error_message = "trust needs either at least one AWS service principal (no wildcards) or federated, not both; source_account must be a 12-digit account ID."
  }
  validation {
    condition     = var.trust.source_arn == null ? true : can(regex("^arn:\\S+$", var.trust.source_arn))
    error_message = "trust.source_arn must be an ARN starting with arn: and contain no whitespace."
  }
  validation {
    condition = var.trust.federated == null ? true : (
      can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/[A-Za-z0-9._~:/-]+$", var.trust.federated.oidc_provider_arn)) &&
      can(regex("^system:serviceaccount:[a-z0-9]([a-z0-9.-]*[a-z0-9])?:[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.trust.federated.subject))
    )
    error_message = "trust.federated.oidc_provider_arn must be arn:aws:iam::<12-digit account>:oidc-provider/<issuer>, and subject must be system:serviceaccount:<namespace>:<serviceaccount> with no wildcards."
  }
  validation {
    condition     = var.trust.federated == null ? true : (!var.trust.tag_session && var.trust.source_account == null && var.trust.source_arn == null)
    error_message = "trust.federated cannot be combined with tag_session, source_account or source_arn."
  }
}

variable "managed_policy_arns" {
  type        = set(string)
  default     = []
  description = "AWS managed policy ARNs to attach. Only the allowlist in locals.tf is accepted; customer managed policies and other AWS managed policies are rejected."
  validation {
    condition     = alltrue([for a in var.managed_policy_arns : contains(local.managed_policy_allowlist, a)])
    error_message = "managed_policy_arns accepts only allowlisted AWS managed policies (see locals.tf)."
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
