variable "name" {
  type        = string
  description = "instance 名稱，也是 `Name` tag。2–63 字元，限小寫英數字與連字號，字母開頭。"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "subnet_id" {
  type        = string
  description = "放 instance 的 private subnet（`subnet-…` 格式）。instance 不會拿到 public IP。"
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8,17}$", var.subnet_id))
    error_message = "subnet_id must look like subnet-0123456789abcdef0."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "instance 的 security group（`sg-…` 格式），至少一個。"
  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "Give at least one security group ID."
  }
  validation {
    condition     = alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", s))])
    error_message = "security_group_ids must look like sg-0123456789abcdef0."
  }
}

variable "instance_profile_name" {
  type        = string
  description = "帶 SSM Session Manager 權限的 instance profile 名稱，1–128 字元。沒有 SSH key，只能透過 Session Manager 進入。"
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.instance_profile_name))
    error_message = "instance_profile_name must be 1-128 chars of letters, digits or +=,.@_-."
  }
}

variable "instance_type" {
  type        = string
  default     = "t4g.nano"
  description = "instance type，例如 `t4g.nano`，必須跟 `architecture` 搭配：Graviton 家族（`t4g`、`m7g`、`c6gn` 等）用 `arm64`，其他用 `x86_64`。"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must look like t4g.nano."
  }
  # Graviton family names carry a g after the generation digit (t4g, c6gn, is4gen). g4dn and m7i-flex do not match. The legacy a1 family is arm64 but is not recognised.
  validation {
    condition     = !contains(["arm64", "x86_64"], var.architecture) || !can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type)) || (can(regex("^[a-z]+[0-9]+[a-z]*g[a-z]*\\.", var.instance_type)) == (var.architecture == "arm64"))
    error_message = "instance_type does not match architecture: Graviton families (t4g, m7g, c6gn, ...) need arm64, all others need x86_64."
  }
}

variable "architecture" {
  type        = string
  default     = "arm64"
  description = "`arm64` 或 `x86_64`，決定用哪個 Amazon Linux 2023 AMI。"
  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "architecture must be arm64 or x86_64."
  }
}

variable "root_volume_size" {
  type        = number
  default     = 8
  description = "root volume 大小（GiB），8–16384 的整數。Amazon Linux 2023 快照是 8 GiB，所以最小 `8`。"
  validation {
    condition     = var.root_volume_size == floor(var.root_volume_size) && var.root_volume_size >= 8 && var.root_volume_size <= 16384
    error_message = "root_volume_size must be a whole number of GiB from 8 to 16384."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "instance 與 root volume 的 tag；`Name` 由 module 加上。"
}
