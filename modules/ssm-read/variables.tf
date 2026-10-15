variable "ssm_prefix" {
  type        = string
  description = "/<project>/<env>, same as ssm-publish."
  validation {
    condition     = can(regex("^/[a-z][a-z0-9-]*/[a-z][a-z0-9]*$", var.ssm_prefix))
    error_message = "ssm_prefix must be /<project>/<env>."
  }
}

variable "strings" {
  type        = map(string)
  default     = {}
  description = "Local name => \"<stack>/<key>\" for String parameters."
  validation {
    condition     = alltrue([for v in values(var.strings) : can(regex("^[a-z][a-z0-9-]*/[a-z][a-z0-9_]*$", v))])
    error_message = "Each value must be <stack>/<key> with a kebab-case stack and a snake_case key."
  }
}

variable "lists" {
  type        = map(string)
  default     = {}
  description = "Local name => \"<stack>/<key>\" for StringList parameters."
  validation {
    condition     = alltrue([for v in values(var.lists) : can(regex("^[a-z][a-z0-9-]*/[a-z][a-z0-9_]*$", v))])
    error_message = "Each value must be <stack>/<key> with a kebab-case stack and a snake_case key."
  }
}
