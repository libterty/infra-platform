variable "ssm_prefix" {
  description = "SSM path prefix for one environment, in the form /<project>/<env>."
  type        = string

  validation {
    condition     = can(regex("^/[a-z][a-z0-9-]*/[a-z][a-z0-9]*$", var.ssm_prefix))
    error_message = "ssm_prefix must be /<project>/<env>."
  }
}

variable "stack" {
  description = "Producing stack name; becomes the path segment after the prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.stack))
    error_message = "stack must be lowercase letters, digits or hyphens."
  }
}

variable "strings" {
  description = "Scalar values published as String parameters, keyed by parameter key. Values must be 1-4096 chars; wrap optional values in JSON."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.strings : can(regex("^[a-z][a-z0-9_]*$", k)) && length(v) > 0 && length(v) <= 4096])
    error_message = "Keys must be snake_case; values must be 1-4096 chars (SSM rejects empty strings; wrap optional values in JSON)."
  }
}

variable "lists" {
  description = "List values published as StringList parameters (comma-joined), keyed by parameter key. Keys must not repeat any key in strings."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.lists : can(regex("^[a-z][a-z0-9_]*$", k)) && length(v) > 0 && alltrue([for e in v : length(e) > 0 && !strcontains(e, ",")])])
    error_message = "Keys must be snake_case; lists must be non-empty and elements must not contain commas."
  }

  validation {
    condition     = length(setintersection(toset(keys(var.strings)), toset(keys(var.lists)))) == 0
    error_message = "A key cannot appear in both strings and lists; both would write the same parameter path."
  }
}
