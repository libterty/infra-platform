variable "app_port" {
  description = "api container 監聽的 port，要跟 `application` stack 的 `app_port` 一致；ALB 只能往 VPC 內這個 port 連線。"
  type        = number
  default     = 8080

  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535 && floor(var.app_port) == var.app_port
    error_message = "app_port must be an integer from 1 to 65535."
  }
}

variable "deletion_protection" {
  description = "是否開啟 ALB 的刪除保護；要 destroy 前先改成 `false` 並 apply。"
  type        = bool
  default     = true
}
