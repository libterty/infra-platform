variable "ca" {
  description = "給裝置憑證用的 AWS Private CA，選填。`null` 不建任何資源（預設，design D4：裝置憑證由 AWS IoT 透過 fleet provisioning 簽發）。`type` 是 `ROOT`（自簽並安裝）或 `SUBORDINATE`（先只產生 CSR，上層 CA 簽好後填 `subordinate_certificate` 再 apply）；common name 固定是 `<project>-<env>-device-ca`，其他 subject 欄位在 `subject` 給。general-purpose CA 約 400 美元／月。"
  type = object({
    type          = optional(string, "ROOT")
    usage_mode    = optional(string, "GENERAL_PURPOSE")
    key_algorithm = optional(string, "EC_prime256v1")
    subject = optional(object({
      organization        = optional(string)
      organizational_unit = optional(string)
      country             = optional(string)
      state               = optional(string)
      locality            = optional(string)
    }), {})
    validity_years                  = optional(number, 10)
    permanent_deletion_time_in_days = optional(number, 30)
    subordinate_certificate = optional(object({
      certificate       = string
      certificate_chain = string
    }))
  })
  default = null

  validation {
    condition     = var.ca == null ? true : contains(["ROOT", "SUBORDINATE"], var.ca.type)
    error_message = "ca.type must be ROOT or SUBORDINATE."
  }
}
