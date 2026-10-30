variable "name" {
  type        = string
  description = "pipeline 名稱，1–100 字元，限英數字、`.`、`@`、`-`、`_`。"

  validation {
    condition     = can(regex("^[A-Za-z0-9.@_-]{1,100}$", var.name))
    error_message = "name must be 1-100 chars of letters, digits, dots, @, hyphens or underscores."
  }
}

variable "role_arn" {
  type        = string
  description = "pipeline 的 service role ARN，由呼叫端建立。role 要能用 `git_source.connection_arn`（`codeconnections:UseConnection` 與 `codestar-connections:UseConnection`）、讀寫 artifact bucket、用 artifact KMS key，以及呼叫各 action 需要的 API。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }
}

variable "artifact_bucket_name" {
  type        = string
  description = "放 pipeline artifact 的 S3 bucket 名稱（不是 ARN），bucket 要跟 pipeline 在同一個 region。"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.artifact_bucket_name))
    error_message = "artifact_bucket_name must be an S3 bucket name (3-63 chars of lowercase letters, digits, dots or hyphens), not an ARN."
  }
}

variable "artifact_kms_key_arn" {
  type        = string
  description = "加密 artifact 用的客戶管理 KMS key ARN（symmetric），必填，不收 alias。key policy 要讓 pipeline role 與各 CodeBuild role 有 `kms:Decrypt`、`kms:GenerateDataKey`。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.artifact_kms_key_arn))
    error_message = "artifact_kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "git_source" {
  type = object({
    connection_arn = string
    repository     = string
    branch         = string
  })
  description = "source stage 的設定，module 用它產生 `CodeStarSourceConnection` action（名稱 `Source`，輸出 artifact `SourceArtifact`，namespace `SourceVariables`），固定 `DetectChanges = \"false\"`、`OutputArtifactFormat = \"CODE_ZIP\"`。`connection_arn` 是 CodeConnections 的 connection ARN（`codeconnections` 或舊的 `codestar-connections` 前綴）；`repository` 是 `owner/name`；`branch` 是手動執行時取的分支。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:(codeconnections|codestar-connections):[a-z0-9-]+:[0-9]{12}:connection/.+$", var.git_source.connection_arn))
    error_message = "git_source.connection_arn must be a CodeConnections connection ARN (arn:<partition>:codeconnections:<region>:<account>:connection/<id>)."
  }

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.git_source.repository))
    error_message = "git_source.repository must be owner/name, such as example-org/example-app."
  }

  validation {
    condition     = length(trimspace(var.git_source.branch)) > 0
    error_message = "git_source.branch must not be empty."
  }
}

variable "stages" {
  type = list(object({
    name = string
    actions = list(object({
      name             = string
      category         = string
      provider         = string
      configuration    = optional(map(string), {})
      input_artifacts  = optional(list(string), [])
      output_artifacts = optional(list(string), [])
      namespace        = optional(string)
      run_order        = optional(number)
    }))
  }))
  description = "source stage 之後的 stage，至少一個，照順序排。stage 名稱不能重複，也不能叫 `Source`。每個 stage 至少一個 action，同一個 stage 裡 action 名稱不能重複。action 的 `category` 只收 `Approval`、`Build`、`Deploy`、`Invoke`、`Test`，`owner` 固定 `AWS`、`version` 固定 `1`；`configuration` 照各 action 的文件填，值可以用 `#{SourceVariables.CommitId}` 這類變數；source 的輸出 artifact 叫 `SourceArtifact`。"

  validation {
    condition     = length(var.stages) >= 1
    error_message = "stages must have at least one stage after the generated Source stage."
  }

  validation {
    condition     = alltrue([for s in var.stages : can(regex("^[A-Za-z0-9.@_-]{1,100}$", s.name))])
    error_message = "stage names must be 1-100 chars of letters, digits, dots, @, hyphens or underscores."
  }

  validation {
    condition     = length(distinct(concat(["Source"], [for s in var.stages : s.name]))) == length(var.stages) + 1
    error_message = "stage names must be unique and must not be Source, which the module uses for the generated source stage."
  }

  validation {
    condition     = alltrue([for s in var.stages : length(s.actions) >= 1])
    error_message = "every stage must have at least one action."
  }

  validation {
    condition     = alltrue([for s in var.stages : length(distinct([for a in s.actions : a.name])) == length(s.actions)])
    error_message = "action names must be unique within a stage."
  }

  validation {
    condition     = alltrue(flatten([for s in var.stages : [for a in s.actions : can(regex("^[A-Za-z0-9.@_-]{1,100}$", a.name))]]))
    error_message = "action names must be 1-100 chars of letters, digits, dots, @, hyphens or underscores."
  }

  validation {
    condition     = alltrue(flatten([for s in var.stages : [for a in s.actions : contains(["Approval", "Build", "Deploy", "Invoke", "Test"], a.category)]]))
    error_message = "action category must be Approval, Build, Deploy, Invoke or Test; the module generates the only Source action."
  }

  validation {
    condition     = alltrue(flatten([for s in var.stages : [for a in s.actions : a.run_order == null || try(a.run_order >= 1 && a.run_order <= 999 && a.run_order == floor(a.run_order), false)]]))
    error_message = "action run_order must be a whole number between 1 and 999."
  }
}

variable "variables" {
  type = map(object({
    default_value = optional(string)
    description   = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "pipeline 層級的變數，key 是變數名稱（1–128 字元，限英數字、`@`、`-`、`_`），action 用 `#{variables.<name>}` 引用；手動執行時可以覆寫。"

  validation {
    condition     = alltrue([for k, _ in var.variables : can(regex("^[A-Za-z0-9@_-]{1,128}$", k))])
    error_message = "variable names must be 1-128 chars of letters, digits, @, hyphens or underscores."
  }
}

variable "execution_mode" {
  type        = string
  default     = "QUEUED"
  nullable    = false
  description = "連續執行的處理方式：`QUEUED`（預設，依序執行、不會被後來的執行蓋掉）、`SUPERSEDED`、`PARALLEL`。"

  validation {
    condition     = contains(["QUEUED", "SUPERSEDED", "PARALLEL"], var.execution_mode)
    error_message = "execution_mode must be QUEUED, SUPERSEDED or PARALLEL."
  }
}

variable "region" {
  type        = string
  default     = null
  description = "pipeline 所在的 region；`null`（預設）用 provider 的 region。artifact bucket 要在同一個 region。"

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.region))
    error_message = "region must be an AWS region such as ap-northeast-1."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "pipeline 的 tag；`Name` 由 module 加上。"
}
