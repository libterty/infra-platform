variable "account_ids" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "要啟用掃描的帳號 ID（12 位數字）。`[]`（預設）用目前的帳號；列其他帳號時，目前帳號要是 Inspector 的委派管理帳號，而且那些帳號已經是成員。"

  validation {
    condition     = alltrue([for a in var.account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "account_ids must be 12-digit AWS account IDs."
  }
}

variable "resource_types" {
  type        = list(string)
  default     = ["EC2", "ECR", "LAMBDA"]
  nullable    = false
  description = "要啟用的掃描類型：`EC2`、`ECR`、`LAMBDA`（Lambda 套件弱點）、`LAMBDA_CODE`（Lambda 程式碼掃描，要同時開 `LAMBDA`）。預設 `EC2`、`ECR`、`LAMBDA`。"

  validation {
    condition     = length(var.resource_types) > 0 && alltrue([for t in var.resource_types : contains(["EC2", "ECR", "LAMBDA", "LAMBDA_CODE"], t)])
    error_message = "resource_types must be a non-empty list of EC2, ECR, LAMBDA or LAMBDA_CODE."
  }

  validation {
    condition     = !contains(var.resource_types, "LAMBDA_CODE") || contains(var.resource_types, "LAMBDA")
    error_message = "LAMBDA_CODE requires LAMBDA in resource_types."
  }
}

variable "organization" {
  type = object({
    auto_enable = object({
      ec2         = optional(bool, true)
      ecr         = optional(bool, true)
      lambda      = optional(bool, true)
      lambda_code = optional(bool, false)
    })
  })
  default     = null
  description = "organization 的自動啟用設定，只在 Inspector 的委派管理帳號給。`auto_enable` 決定新成員帳號自動開哪些掃描：`ec2`、`ecr`、`lambda` 預設 `true`，`lambda_code` 預設 `false`（要同時開 `lambda`）。`null`（預設）時不管理 organization 設定。"

  validation {
    condition     = var.organization == null || !try(var.organization.auto_enable.lambda_code, false) || try(var.organization.auto_enable.lambda, false)
    error_message = "organization.auto_enable.lambda_code requires organization.auto_enable.lambda."
  }
}

variable "region" {
  type        = string
  default     = null
  description = "Inspector 所在的 region；`null`（預設）用 provider 的 region。Inspector 是 regional 服務，每個 region 各呼叫一次。"

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.region))
    error_message = "region must be an AWS region such as ap-northeast-1."
  }
}
