variable "cluster_name" {
  type        = string
  description = "EKS cluster 名稱，用在 ARN 與 Karpenter policy 的 cluster tag 條件。1–100 字元，限英數字、`-`、`_`，首字元須為英數字。"
  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9_-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must be 1-100 chars of letters, digits, hyphen or underscore, starting with a letter or digit."
  }
}

variable "region" {
  type        = string
  description = "cluster 所在 region，例如 `ap-northeast-1`。"
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like ap-northeast-1."
  }
}

variable "account_id" {
  type        = string
  description = "cluster 所在的 12 位數 AWS 帳號 ID。"
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit account ID."
  }
}

variable "partition" {
  type        = string
  default     = "aws"
  description = "這個 module 組出的 ARN 用的 AWS partition：`aws`、`aws-cn` 或 `aws-us-gov`。LB Controller policy 是官方檔案，不受影響。"
  validation {
    condition     = contains(["aws", "aws-cn", "aws-us-gov"], var.partition)
    error_message = "partition must be aws, aws-cn or aws-us-gov."
  }
}

variable "load_balancer_controller_version" {
  type        = string
  default     = "3.6.1"
  description = "要輸出哪個版本的 AWS Load Balancer Controller 官方 IAM policy。只接受 module 在 `policies/aws-load-balancer-controller/` 附的版本（目前是 `3.6.0`、`3.6.1`）。"
  validation {
    condition     = contains(keys(local.load_balancer_controller_policies), var.load_balancer_controller_version)
    error_message = "load_balancer_controller_version must be one of the vendored versions (see policies/aws-load-balancer-controller/)."
  }
}

variable "karpenter" {
  type = object({
    version                 = optional(string, "1.15.0")
    node_role_arn           = string
    interruption_queue_name = string
  })
  default     = null
  description = "Karpenter controller policy 的設定；`null` 時不輸出 Karpenter policy。欄位：`version`（預設 `1.15.0`，只接受 `local.karpenter_supported_versions` 列的版本，目前只有 `1.15.0`）、`node_role_arn`（controller 唯一能 pass 給 EC2 的 role，必須是不含萬用字元的 IAM role ARN）、`interruption_queue_name`（controller 可讀的 SQS queue，1–80 字元，限英數字、`-`、`_`）。"
  validation {
    condition     = var.karpenter == null ? true : contains(local.karpenter_supported_versions, var.karpenter.version)
    error_message = "karpenter.version must be one of the supported versions (see locals.tf and policies/karpenter/)."
  }
  validation {
    condition     = var.karpenter == null ? true : can(regex("^arn:(aws|aws-cn|aws-us-gov):iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.karpenter.node_role_arn))
    error_message = "karpenter.node_role_arn must be an IAM role ARN with no wildcard."
  }
  validation {
    condition     = var.karpenter == null ? true : can(regex("^[A-Za-z0-9_-]{1,80}$", var.karpenter.interruption_queue_name))
    error_message = "karpenter.interruption_queue_name must be 1-80 chars of letters, digits, hyphen or underscore."
  }
}
