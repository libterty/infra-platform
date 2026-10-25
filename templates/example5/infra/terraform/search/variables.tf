variable "engine_version" {
  description = "OpenSearch 引擎版本，格式 `OpenSearch_<主版號>.<次版號>`，例如 `OpenSearch_2.19`。"
  type        = string
}

variable "hot" {
  description = "hot（data）節點：`instance_type`、`instance_count`（至少 2，且不少於 `availability_zone_count`）、`ebs`（`volume_size` 單位 GiB，`volume_type` 預設 `gp3`）。告警的剩餘空間門檻取 `volume_size` 的 25%。"
  type = object({
    instance_type  = string
    instance_count = number
    ebs = object({
      volume_size = number
      volume_type = optional(string, "gp3")
    })
  })
}

variable "dedicated_master" {
  description = "dedicated master 節點：`instance_type`、`count`（3，或 5 以上）。`null` 表示不用；啟用 `warm` 時必填，且不能是 T2／T3。"
  type = object({
    instance_type = string
    count         = number
  })
  default = null
}

variable "warm" {
  description = "UltraWarm 節點：`instance_type`（`ultrawarm1.medium.search`、`ultrawarm1.large.search`、`ultrawarm1.xlarge.search`）、`count`。`null` 表示不用，同時不建 warm 相關告警。"
  type = object({
    instance_type = string
    count         = number
  })
  default = null
}

variable "cold_storage" {
  description = "是否啟用 cold storage，必須同時有 `warm`。`false` 時不建 warm 到 cold 的搬移告警。"
  type        = bool
  default     = false
}

variable "availability_zone_count" {
  description = "domain 使用的 AZ 數（2 或 3），要等於 network stack 發布的 data subnet 數量。"
  type        = number
  default     = 2
}

variable "log_retention_days" {
  description = "domain 的 CloudWatch log group 保留天數，必須是 CloudWatch Logs 支援的值。"
  type        = number
  default     = 30
}
