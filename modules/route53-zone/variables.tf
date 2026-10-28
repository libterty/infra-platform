variable "name" {
  type        = string
  description = "hosted zone 的網域名稱，例如 `dev.example.com`。小寫、至少兩層、結尾不帶 `.`，最長 253 字元。"

  validation {
    condition     = !endswith(var.name, ".")
    error_message = "name must not end with a dot; use dev.example.com, not dev.example.com."
  }

  validation {
    condition     = length(var.name) <= 253 && can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.name))
    error_message = "name must be a lower-case DNS name with at least two labels, such as dev.example.com."
  }
}

variable "comment" {
  type        = string
  default     = null
  description = "zone 的說明；`null` 時用 AWS 的預設值（`Managed by Terraform`）。"
}

variable "private_vpc_ids" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "要關聯的 VPC ID（`vpc-` 開頭）。有值就建 private zone，只在這些 VPC 內解析；空的（預設）就建 public zone。VPC 必須在 provider 的 region。"

  validation {
    condition     = alltrue([for id in var.private_vpc_ids : can(regex("^vpc-[0-9a-f]{8,17}$", id))])
    error_message = "private_vpc_ids must be VPC IDs such as vpc-0123456789abcdef0."
  }
}

variable "force_destroy" {
  type        = bool
  default     = false
  nullable    = false
  description = "destroy 時是否連 zone 裡的 record 一起刪（預設 `false`）。`false` 時 zone 裡還有 Terraform 以外建的 record 就刪不掉，避免誤刪。"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "zone 的 tag；`Name` 由 module 加上（值是 `name`）。"
}
