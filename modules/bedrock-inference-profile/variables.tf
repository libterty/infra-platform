variable "name_prefix" {
  type        = string
  description = "profile 名稱前綴，名稱是 `<name_prefix>-<key>`，總長不超過 64 字元。"
}

variable "profiles" {
  type = map(object({
    copy_from   = string
    description = optional(string)
  }))
  description = "application inference profile，key 是 profile 短名；給 `{}` 就什麼都不建。欄位：`copy_from`（必填，foundation model 或 system inference profile 的完整 ARN，不能含 `*`；system inference profile 必須在目前的帳號）、`description`（預設 `null`）。完整名稱限字母、數字、`:`、`.`，中間可夾一個空白、`_` 或 `-`。"

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
  description = "套用到每個 profile 的 tag，Cost Explorer 依這些 tag 拆模型費用；`Name` 自動設成 profile 名稱。"
}
