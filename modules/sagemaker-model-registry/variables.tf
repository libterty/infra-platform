variable "name" {
  type        = string
  description = "model package group 名稱，1–63 字元，限英數字與 `-`，開頭結尾是英數字。"

  validation {
    condition     = length(var.name) <= 63 && can(regex("^[a-zA-Z0-9](-*[a-zA-Z0-9])*$", var.name))
    error_message = "name must be 1-63 chars of letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "model package group 的說明，最多 1024 字元；`null` 不設。"

  validation {
    condition     = var.description == null || length(coalesce(var.description, " ")) <= 1024
    error_message = "description must be at most 1024 characters."
  }
}

variable "cross_account_read_principals" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "可以唯讀這個 group 的其他帳號：12 位數帳號 ID（轉成 `arn:<partition>:iam::<id>:root`）或 IAM role ARN。有值時建 resource policy，只給 `sagemaker:DescribeModelPackageGroup`、`sagemaker:DescribeModelPackage`、`sagemaker:ListModelPackages` 與 `sagemaker:CreateModel`（讓對方從 model package 建 model）；空的就不建。不收 `*`。"

  validation {
    condition     = alltrue([for p in var.cross_account_read_principals : !strcontains(p, "*")])
    error_message = "cross_account_read_principals must not contain \"*\"."
  }

  validation {
    condition = alltrue([for p in var.cross_account_read_principals :
      can(regex("^[0-9]{12}$", p)) || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[a-zA-Z0-9+=,.@_/-]+$", p))
    ])
    error_message = "every cross_account_read_principals entry must be a 12-digit account ID or an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "model package group 的 tag；`Name` 由 module 加上。"
}
