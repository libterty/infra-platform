variable "name" {
  type        = string
  description = "connection 名稱，1–32 字元。"

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 32
    error_message = "name must be 1-32 characters."
  }
}

variable "provider_type" {
  type        = string
  default     = "GitHub"
  nullable    = false
  description = "程式碼平台：`GitHub`（預設）、`GitHubEnterpriseServer`、`GitLab`、`GitLabSelfManaged`、`Bitbucket`。自架的 `GitHubEnterpriseServer`、`GitLabSelfManaged` 必須給 `host_arn`。"

  validation {
    condition     = contains(["GitHub", "GitHubEnterpriseServer", "GitLab", "GitLabSelfManaged", "Bitbucket"], var.provider_type)
    error_message = "provider_type must be GitHub, GitHubEnterpriseServer, GitLab, GitLabSelfManaged or Bitbucket."
  }
}

variable "host_arn" {
  type        = string
  default     = null
  description = "自架平台的 host ARN（`arn:<partition>:codeconnections:<region>:<account>:host/<id>`，舊的 `codestar-connections` 也接受）。只有 `GitHubEnterpriseServer`、`GitLabSelfManaged` 要給，雲端平台不能給。host 不由這個 module 建。"

  validation {
    condition     = var.host_arn == null || can(regex("^arn:aws[a-z-]*:(codeconnections|codestar-connections):[a-z0-9-]+:[0-9]{12}:host/[A-Za-z0-9_.-]+$", var.host_arn))
    error_message = "host_arn must be a CodeConnections host ARN (arn:<partition>:codeconnections:<region>:<account>:host/<id>)."
  }

  validation {
    condition     = contains(["GitHubEnterpriseServer", "GitLabSelfManaged"], var.provider_type) == (var.host_arn != null)
    error_message = "host_arn is required for GitHubEnterpriseServer and GitLabSelfManaged, and must be null for GitHub, GitLab and Bitbucket."
  }
}

variable "region" {
  type        = string
  default     = null
  description = "connection 所在的 region；`null`（預設）用 provider 的 region。"

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.region))
    error_message = "region must be an AWS region such as us-east-1."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "connection 的 tag；`Name` 由 module 加上。"
}
