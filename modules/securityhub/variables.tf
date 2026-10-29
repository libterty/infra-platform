variable "standards" {
  type        = list(string)
  default     = ["fsbp", "cis"]
  nullable    = false
  description = "要訂閱的標準短名，module 換成 region 對應的 ARN：`fsbp`（AWS Foundational Security Best Practices v1.0.0）、`cis`（CIS AWS Foundations Benchmark v5.0.0）。預設兩個都訂。"

  validation {
    condition     = alltrue([for s in var.standards : contains(["fsbp", "cis"], s)])
    error_message = "standards must only contain fsbp or cis."
  }
}

variable "control_finding_generator" {
  type        = string
  default     = "SECURITY_CONTROL"
  nullable    = false
  description = "`SECURITY_CONTROL`（預設，同一個 control 在多個標準只產生一筆 finding）或 `STANDARD_CONTROL`（每個標準各一筆）。Organizations 模式只有管理員帳號能改。"

  validation {
    condition     = contains(["SECURITY_CONTROL", "STANDARD_CONTROL"], var.control_finding_generator)
    error_message = "control_finding_generator must be SECURITY_CONTROL or STANDARD_CONTROL."
  }
}

variable "auto_enable_controls" {
  type        = bool
  default     = true
  nullable    = false
  description = "已訂閱的標準新增 control 時是否自動啟用（預設 `true`）。"
}

variable "finding_aggregator" {
  type = object({
    linking_mode = string
    regions      = optional(list(string), [])
  })
  default     = null
  description = "跨 region 彙整 finding 到這個 region。`linking_mode`：`ALL_REGIONS`、`ALL_REGIONS_EXCEPT_SPECIFIED`、`SPECIFIED_REGIONS`、`NO_REGIONS`；`ALL_REGIONS_EXCEPT_SPECIFIED` 與 `SPECIFIED_REGIONS` 要給 `regions`（要排除或納入的 region），`ALL_REGIONS` 與 `NO_REGIONS` 不能給。`null`（預設）時不建 aggregator。"

  validation {
    condition     = var.finding_aggregator == null || contains(["ALL_REGIONS", "ALL_REGIONS_EXCEPT_SPECIFIED", "SPECIFIED_REGIONS", "NO_REGIONS"], try(var.finding_aggregator.linking_mode, ""))
    error_message = "finding_aggregator.linking_mode must be ALL_REGIONS, ALL_REGIONS_EXCEPT_SPECIFIED, SPECIFIED_REGIONS or NO_REGIONS."
  }

  validation {
    condition = var.finding_aggregator == null || (
      contains(["ALL_REGIONS_EXCEPT_SPECIFIED", "SPECIFIED_REGIONS"], try(var.finding_aggregator.linking_mode, "")) == (length(try(var.finding_aggregator.regions, [])) > 0)
    )
    error_message = "finding_aggregator.regions is required for ALL_REGIONS_EXCEPT_SPECIFIED and SPECIFIED_REGIONS and not allowed otherwise."
  }

  validation {
    condition     = var.finding_aggregator == null || alltrue([for r in try(var.finding_aggregator.regions, []) : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", r))])
    error_message = "finding_aggregator.regions must be AWS regions such as us-east-1."
  }
}

variable "organization" {
  type = object({
    auto_enable           = bool
    auto_enable_standards = string
  })
  default     = null
  description = "organization 設定（local configuration），只在 Security Hub 的委派管理帳號給。`auto_enable` 是新成員帳號是否自動啟用 Security Hub；`auto_enable_standards` 是 `DEFAULT`（新成員自動開 AWS 的預設標準：FSBP 與 CIS v1.2.0）或 `NONE`。`null`（預設）時不管理 organization 設定。"

  validation {
    condition     = var.organization == null || contains(["DEFAULT", "NONE"], try(var.organization.auto_enable_standards, ""))
    error_message = "organization.auto_enable_standards must be DEFAULT or NONE."
  }
}

variable "region" {
  type        = string
  default     = null
  description = "Security Hub 所在的 region；`null`（預設）用 provider 的 region。標準 ARN 也用這個 region 組出。Security Hub 是 regional 服務，每個 region 各呼叫一次。"

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.region))
    error_message = "region must be an AWS region such as ap-northeast-1."
  }
}
