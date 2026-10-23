variable "ssm_prefix" {
  description = "一個環境的 SSM 路徑前綴，格式 `/<project>/<env>`。`<project>` 小寫字母開頭，可含數字與連字號；`<env>` 小寫字母開頭，可含數字。"
  type        = string

  validation {
    condition     = can(regex("^/[a-z][a-z0-9-]*/[a-z][a-z0-9]*$", var.ssm_prefix))
    error_message = "ssm_prefix must be /<project>/<env>."
  }
}

variable "stack" {
  description = "產出這些值的 stack 名稱，會成為前綴後面的那一段路徑。小寫字母開頭，可含數字與連字號。"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.stack))
    error_message = "stack must be lowercase letters, digits or hyphens."
  }
}

variable "strings" {
  description = "以 `String` 參數發布的純量值，key 為參數 key（snake_case），值 1–4096 字元。可有可無的值請包成 JSON。"
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.strings : can(regex("^[a-z][a-z0-9_]*$", k)) && length(v) > 0 && length(v) <= 4096])
    error_message = "Keys must be snake_case; values must be 1-4096 chars (SSM rejects empty strings; wrap optional values in JSON)."
  }
}

variable "lists" {
  description = "以 `StringList` 參數（逗號串接）發布的清單，key 為參數 key（snake_case），不可跟 `strings` 的 key 重複。清單不可為空，元素不可為空字串或含逗號。"
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
