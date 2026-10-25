variable "type" {
  type        = string
  description = "CA 類型：`ROOT`（module 建自簽的 root 憑證並安裝）或 `SUBORDINATE`（module 只產生 CSR，由上層 CA 簽好後透過 `subordinate_certificate` 安裝）。"

  validation {
    condition     = contains(["ROOT", "SUBORDINATE"], var.type)
    error_message = "type must be ROOT or SUBORDINATE."
  }
}

variable "usage_mode" {
  type        = string
  default     = "GENERAL_PURPOSE"
  nullable    = false
  description = "用途：`GENERAL_PURPOSE`（約 400 美元／月）或 `SHORT_LIVED_CERTIFICATE`（憑證最長 7 天，約 50 美元／月）。"

  validation {
    condition     = contains(["GENERAL_PURPOSE", "SHORT_LIVED_CERTIFICATE"], var.usage_mode)
    error_message = "usage_mode must be GENERAL_PURPOSE or SHORT_LIVED_CERTIFICATE."
  }
}

variable "key_algorithm" {
  type        = string
  default     = "EC_prime256v1"
  nullable    = false
  description = "CA 金鑰演算法：`EC_prime256v1`（預設）、`EC_secp384r1`、`EC_secp521r1`、`RSA_2048`、`RSA_3072`、`RSA_4096`。簽章演算法由 module 依金鑰決定（P-256 與 RSA 用 SHA-256、P-384 用 SHA-384、P-521 用 SHA-512）。"

  validation {
    condition     = contains(["EC_prime256v1", "EC_secp384r1", "EC_secp521r1", "RSA_2048", "RSA_3072", "RSA_4096"], var.key_algorithm)
    error_message = "key_algorithm must be EC_prime256v1, EC_secp384r1, EC_secp521r1, RSA_2048, RSA_3072 or RSA_4096."
  }
}

variable "subject" {
  type = object({
    common_name         = string
    organization        = optional(string)
    organizational_unit = optional(string)
    country             = optional(string)
    state               = optional(string)
    locality            = optional(string)
  })
  description = "CA 憑證的 X.500 subject。`common_name` 必填（1–64 字元，也當 `Name` tag）；`country` 是兩碼大寫國碼。"

  validation {
    condition     = length(var.subject.common_name) >= 1 && length(var.subject.common_name) <= 64
    error_message = "subject.common_name must be 1-64 characters."
  }

  validation {
    condition     = var.subject.country == null || can(regex("^[A-Z]{2}$", var.subject.country))
    error_message = "subject.country must be a two-letter upper-case country code."
  }
}

variable "validity_years" {
  type        = number
  default     = 10
  nullable    = false
  description = "`ROOT` 自簽憑證的有效年數，1–30（預設 10）。`SUBORDINATE` 的有效期由上層 CA 簽發時決定，這個值不使用。"

  validation {
    condition     = var.validity_years >= 1 && var.validity_years <= 30 && var.validity_years == floor(var.validity_years)
    error_message = "validity_years must be a whole number between 1 and 30."
  }
}

variable "permanent_deletion_time_in_days" {
  type        = number
  default     = 30
  nullable    = false
  description = "刪除 CA 後可以還原的天數，7–30（預設 30）。期間內 CA 仍可還原，過了就永久刪除。"

  validation {
    condition     = var.permanent_deletion_time_in_days >= 7 && var.permanent_deletion_time_in_days <= 30 && var.permanent_deletion_time_in_days == floor(var.permanent_deletion_time_in_days)
    error_message = "permanent_deletion_time_in_days must be a whole number between 7 and 30."
  }
}

variable "subordinate_certificate" {
  type = object({
    certificate       = string
    certificate_chain = string
  })
  default     = null
  description = "上層 CA 用 `csr` 簽好的憑證與憑證鏈（PEM），只在 `type = \"SUBORDINATE\"` 時給；給了就安裝到 CA。`null` 時 CA 停在等待憑證的狀態，只輸出 CSR。"

  validation {
    condition     = var.subordinate_certificate == null || var.type == "SUBORDINATE"
    error_message = "subordinate_certificate is only accepted when type is SUBORDINATE."
  }

  validation {
    condition = var.subordinate_certificate == null || (
      startswith(trimspace(try(var.subordinate_certificate.certificate, "")), "-----BEGIN CERTIFICATE-----") &&
      startswith(trimspace(try(var.subordinate_certificate.certificate_chain, "")), "-----BEGIN CERTIFICATE-----")
    )
    error_message = "subordinate_certificate.certificate and certificate_chain must be PEM certificates."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "CA 的 tag；`Name` 由 module 加上（值是 `subject.common_name`）。"
}
