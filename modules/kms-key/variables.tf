variable "name" {
  type        = string
  description = "Key alias without the alias/ prefix."

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_-]{1,250}$", var.name)) && !startswith(var.name, "aws/")
    error_message = "name must be 1-250 chars of letters, digits, /, _ or -, and must not start with aws/."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "Key description."
}

variable "deletion_window_in_days" {
  type        = number
  default     = 30
  description = "Waiting period before a deleted key is removed."

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "administrator_arns" {
  type        = list(string)
  default     = []
  description = "Extra IAM principals allowed to administer the key. The account root is always included."

  validation {
    condition     = alltrue([for a in var.administrator_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/[^*]+$", a))])
    error_message = "administrator_arns must be IAM role or user ARNs; wildcards are not allowed."
  }
}

variable "service_principals" {
  type = map(object({
    actions = optional(list(string), ["kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"])
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default     = {}
  description = "Service principal (e.g. logs.ap-northeast-1.amazonaws.com) => actions and conditions it gets on this key."

  validation {
    condition     = alltrue([for k in keys(var.service_principals) : can(regex("^[a-z0-9.-]+\\.amazonaws\\.com$", k))])
    error_message = "Keys must be AWS service principals ending in .amazonaws.com; * is not allowed."
  }

  validation {
    condition     = alltrue(flatten([for v in values(var.service_principals) : [for a in v.actions : a != "*" && a != "kms:*"]]))
    error_message = "Service principals must not get * or kms:*."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the key. Name is added by the module."
}
