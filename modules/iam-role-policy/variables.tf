variable "role_arn" {
  type        = string
  description = "Existing role to attach the policies to. Must have no path; the role name is taken from the last ARN segment."
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[a-zA-Z0-9+=,.@_-]{1,64}$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN without a path."
  }
}

variable "policies" {
  type        = map(string)
  description = "Policy name => policy JSON built with jsonencode()."
  validation {
    condition     = length(var.policies) > 0 && alltrue([for p in values(var.policies) : can(jsondecode(p).Statement[0])])
    error_message = "Give at least one policy; each must be a JSON document with a Statement."
  }
  validation {
    condition = alltrue(flatten([
      for p in values(var.policies) : [
        for s in try(jsondecode(p).Statement, []) : [
          for a in flatten([try(s.Action, [])]) : a != "*" && !endswith(a, ":*")
        ] if try(s.Effect, "Allow") == "Allow"
      ]
    ]))
    error_message = "Allow statements must not use * or service:* actions."
  }
  validation {
    condition = alltrue(flatten([
      for p in values(var.policies) : [
        for s in try(jsondecode(p).Statement, []) : !(try(s.Effect, "Allow") == "Allow" && try(s.NotAction, null) != null)
      ]
    ]))
    error_message = "Allow statements must not use NotAction."
  }
  validation {
    condition = alltrue(flatten([
      for p in values(var.policies) : [
        for s in try(jsondecode(p).Statement, []) : !(try(s.Effect, "Allow") == "Allow" && try(s.NotResource, null) != null)
      ]
    ]))
    error_message = "Allow statements must not use NotResource."
  }
}
