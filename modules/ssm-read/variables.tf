variable "ssm_prefix" {
  type        = string
  description = "`/<project>/<env>`，跟 `ssm-publish` 相同。"
  validation {
    condition     = can(regex("^/[a-z][a-z0-9-]*/[a-z][a-z0-9]*$", var.ssm_prefix))
    error_message = "ssm_prefix must be /<project>/<env>."
  }
}

variable "strings" {
  type        = map(string)
  default     = {}
  description = "本地名稱對應 `<stack>/<key>`，讀 `String` 參數。"
  validation {
    condition     = alltrue([for v in values(var.strings) : can(regex("^[a-z][a-z0-9-]*/[a-z][a-z0-9_]*$", v))])
    error_message = "Each value must be <stack>/<key> with a kebab-case stack and a snake_case key."
  }
}

variable "lists" {
  type        = map(string)
  default     = {}
  description = "本地名稱對應 `<stack>/<key>`，讀 `StringList` 參數。"
  validation {
    condition     = alltrue([for v in values(var.lists) : can(regex("^[a-z][a-z0-9-]*/[a-z][a-z0-9_]*$", v))])
    error_message = "Each value must be <stack>/<key> with a kebab-case stack and a snake_case key."
  }
}
