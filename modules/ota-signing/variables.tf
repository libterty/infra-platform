variable "name" {
  type        = string
  description = "signing profile 名稱，2–64 字元，限英數字與 `_`（Signer 不收連字號）。"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{2,64}$", var.name))
    error_message = "name must be 2-64 chars of letters, digits or underscores."
  }
}

variable "platform_id" {
  type        = string
  description = "簽章 platform：`AWSIoTDeviceManagement-SHA256-ECDSA`、`AmazonFreeRTOS-Default` 或 `AmazonFreeRTOS-TI-CC3220SF`。"

  validation {
    condition     = contains(["AWSIoTDeviceManagement-SHA256-ECDSA", "AmazonFreeRTOS-Default", "AmazonFreeRTOS-TI-CC3220SF"], var.platform_id)
    error_message = "platform_id must be AWSIoTDeviceManagement-SHA256-ECDSA, AmazonFreeRTOS-Default or AmazonFreeRTOS-TI-CC3220SF."
  }
}

variable "certificate_arn" {
  type        = string
  description = "在 Terraform 外匯入 ACM 的 code signing 憑證 ARN，必填。Signer 只替 Lambda 與 container image 管理金鑰，IoT 的三種 platform 都要自備憑證；這個 module 不收私鑰。"

  validation {
    condition     = var.certificate_arn != null && can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f-]{36}$", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN (arn:<partition>:acm:<region>:<account>:certificate/<id>)."
  }
}

variable "signing_parameters" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "簽章參數，例如 `{ certname = \"ota_signer_pub.pem\" }`（裝置上驗章憑證的路徑，FreeRTOS OTA 會用到）。空的就不送。"
}

variable "start_job_principals" {
  type        = set(string)
  default     = []
  nullable    = false
  description = "可以用這個 profile 開簽章 job（`signer:StartSigningJob`）的 IAM role ARN。空的就不建 profile permission。"

  validation {
    condition     = alltrue([for p in var.start_job_principals : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[a-zA-Z0-9+=,.@_/-]+$", p))])
    error_message = "start_job_principals must be IAM role ARNs (arn:<partition>:iam::<account>:role/<name>)."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "signing profile 的 tag；`Name` 由 module 加上。"
}
