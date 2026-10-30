variable "api_bootstrap_image_tag" {
  description = "api service 第一次建立時用的映像 tag（不可用 `latest`）。apply 前要先手動把這個 tag 推到 `containerimage` 的 api repository（K10）；之後由 pipeline 部署，改這個值不會換掉執行中的映像。"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.api_bootstrap_image_tag)) && var.api_bootstrap_image_tag != "latest"
    error_message = "api_bootstrap_image_tag must be an image tag other than latest."
  }
}

variable "fn_bootstrap_image_tag" {
  description = "fn 函式第一次建立時用的映像 tag（不可用 `latest`）。apply 前要先手動把這個 tag 推到 `containerimage` 的 fn repository（K10）；之後由 pipeline 部署，改這個值不會換掉 alias 指的版本。"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.fn_bootstrap_image_tag)) && var.fn_bootstrap_image_tag != "latest"
    error_message = "fn_bootstrap_image_tag must be an image tag other than latest."
  }
}

variable "app_port" {
  description = "api container 監聽的 port，要跟 `loadbalancer` stack 的 `app_port` 一致。"
  type        = number
  default     = 8080

  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535 && floor(var.app_port) == var.app_port
    error_message = "app_port must be an integer from 1 to 65535."
  }
}

variable "api_desired_count" {
  description = "api service 的 task 數。"
  type        = number

  validation {
    condition     = var.api_desired_count >= 1 && floor(var.api_desired_count) == var.api_desired_count
    error_message = "api_desired_count must be a whole number of at least 1."
  }
}

variable "api_cpu" {
  description = "api task 的 CPU 單位。"
  type        = number
  default     = 256
}

variable "api_memory" {
  description = "api task 的記憶體（MiB），要能跟 `api_cpu` 搭配。"
  type        = number
  default     = 512
}

variable "api_health_check_path" {
  description = "ALB 對 api task 做 health check 的路徑。"
  type        = string
  default     = "/health"
}

variable "fn_memory_size" {
  description = "fn 函式的記憶體（MB）。"
  type        = number
  default     = 512
}

variable "fn_timeout" {
  description = "fn 函式的逾時秒數。"
  type        = number
  default     = 30
}

variable "log_retention_days" {
  description = "api service、fn 函式與 Container Insights log 的保留天數。"
  type        = number
}
