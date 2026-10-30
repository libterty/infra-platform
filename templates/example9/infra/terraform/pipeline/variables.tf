variable "repository" {
  description = "三條 pipeline 共用的應用程式 GitHub repo，`owner/name` 格式。foundation 的 connection 授權時，GitHub App 要裝在這個 repo。"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.repository))
    error_message = "repository must be owner/name, such as example-org/example-app."
  }
}

variable "branch" {
  description = "pipeline 手動執行時部署的分支。這個分支應該只能透過 PR 合併（design 4.1）。"
  type        = string

  validation {
    condition     = length(trimspace(var.branch)) > 0
    error_message = "branch must not be empty."
  }
}

variable "approval_required" {
  description = "是否在 Deploy 之前加 manual approval stage（K6：dev 不加、sit 加）。"
  type        = bool
}

variable "fn_deploy_strategy" {
  description = "fn pipeline 的 Lambda 部署 action 切換 alias 的方式，例如 `AllAtOnce`、`Canary10Percent5Minutes`、`Linear10PercentEvery1Minute`。"
  type        = string

  validation {
    condition     = can(regex("^(AllAtOnce|Canary[0-9]+Percent[0-9]+Minutes?|Linear[0-9]+PercentEvery[0-9]+Minutes?)$", var.fn_deploy_strategy))
    error_message = "fn_deploy_strategy must be AllAtOnce, Canary<n>Percent<m>Minutes or Linear<n>PercentEvery<m>Minutes."
  }
}

variable "log_retention_days" {
  description = "建置專案 log 的保留天數。"
  type        = number
}
