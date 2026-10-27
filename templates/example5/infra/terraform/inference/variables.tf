variable "model_package_arn" {
  description = "要部署的 model package 版本 ARN（`arn:aws:sagemaker:<region>:<account>:model-package/<project>-<env>-models/<version>`），要是 `ml` stack 的 group 裡核准過的版本。`null`（預設）不建任何資源（design K21）。"
  type        = string
  default     = null

  validation {
    condition     = var.model_package_arn == null || can(regex("^arn:aws[a-z-]*:sagemaker:[a-z0-9-]+:[0-9]{12}:model-package/[a-zA-Z0-9-]+/[0-9]+$", var.model_package_arn))
    error_message = "model_package_arn must be a versioned model package ARN (arn:<partition>:sagemaker:<region>:<account>:model-package/<group>/<version>)."
  }
}

variable "serverless" {
  description = "改用 serverless variant，選填：`memory_size_in_mb`（1024–6144，1024 的倍數）、`max_concurrency`（1–200）。serverless 不能放在 VPC、不能 data capture、不支援 network isolation。`null`（預設）用一台 `ml.m5.large` 的 instance variant。"
  type = object({
    memory_size_in_mb = number
    max_concurrency   = number
  })
  default = null
}
