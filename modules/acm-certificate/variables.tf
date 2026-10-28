variable "domain_name" {
  type        = string
  description = "憑證的主要名稱，例如 `dev.example.com` 或 `*.dev.example.com`。小寫、結尾不帶 `.`；wildcard 只能是最左邊一整層（`*.`）。名稱要在 `zone_id` 這個 zone 底下。"

  validation {
    condition     = !strcontains(trimprefix(var.domain_name, "*."), "*")
    error_message = "domain_name may only use a wildcard as the whole left-most label, such as *.dev.example.com."
  }

  validation {
    condition     = length(var.domain_name) <= 253 && can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.domain_name))
    error_message = "domain_name must be a lower-case DNS name without a trailing dot, such as dev.example.com."
  }
}

variable "subject_alternative_names" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "其他名稱（SAN），最多 9 個，加上 `domain_name` 共 10 個（ACM 的預設上限）。格式規則跟 `domain_name` 一樣。apex 和 `*.apex` 共用同一筆驗證 record。"

  validation {
    condition     = length(var.subject_alternative_names) <= 9
    error_message = "subject_alternative_names allows at most 9 names; with domain_name that is the ACM default limit of 10."
  }

  validation {
    condition     = alltrue([for n in var.subject_alternative_names : !strcontains(trimprefix(n, "*."), "*")])
    error_message = "subject_alternative_names may only use a wildcard as the whole left-most label, such as *.dev.example.com."
  }

  validation {
    condition     = alltrue([for n in var.subject_alternative_names : length(n) <= 253 && can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", n))])
    error_message = "subject_alternative_names must be lower-case DNS names without a trailing dot, such as api.dev.example.com."
  }
}

variable "zone_id" {
  type        = string
  description = "寫入 DNS 驗證 record 的 hosted zone ID（`route53-zone` 的 `zone_id` 輸出）。憑證的所有名稱都要在這個 zone 底下，而且 zone 要已經完成委派。"

  validation {
    condition     = can(regex("^Z[A-Z0-9]{1,31}$", var.zone_id))
    error_message = "zone_id must be a hosted zone ID such as Z0123456789ABCDEFGHIJ."
  }
}

variable "region" {
  type        = string
  default     = null
  description = "憑證所在的 region；`null`（預設）用 provider 的 region。給 CloudFront 用的憑證一定要 `\"us-east-1\"`。"

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.region))
    error_message = "region must be an AWS region such as us-east-1."
  }
}

variable "key_algorithm" {
  type        = string
  default     = "RSA_2048"
  nullable    = false
  description = "憑證金鑰演算法：`RSA_2048`（預設，相容性最好）、`EC_prime256v1`、`EC_secp384r1`。"

  validation {
    condition     = contains(["RSA_2048", "EC_prime256v1", "EC_secp384r1"], var.key_algorithm)
    error_message = "key_algorithm must be RSA_2048, EC_prime256v1 or EC_secp384r1."
  }
}

variable "validation_timeout" {
  type        = string
  default     = "45m"
  nullable    = false
  description = "等待憑證簽發的時間上限，Go duration 格式（例如 `45m`、`1h30m`，預設 `45m`）。zone 的委派還沒生效時，apply 會等到這個時間才失敗。"

  validation {
    condition     = var.validation_timeout != "" && can(regex("^([0-9]+h)?([0-9]+m)?([0-9]+s)?$", var.validation_timeout))
    error_message = "validation_timeout must be a duration such as 45m or 1h30m."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "憑證的 tag。module 不加 `Name`，因為 ACM 的 tag 值不收 wildcard 的 `*`。"
}
