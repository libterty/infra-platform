variable "warehouse_mode" {
  description = "Redshift 型態：`serverless` 或 `provisioned`。切換會被 `guard.tf` 的 `prevent_destroy` 擋下，步驟見 README 的切換 runbook。對應的物件（`serverless` 或 `provisioned`）必填，另一個必須是 `null`。"
  type        = string

  validation {
    condition     = contains(["serverless", "provisioned"], var.warehouse_mode)
    error_message = "warehouse_mode must be serverless or provisioned."
  }
}

variable "serverless" {
  description = "Serverless 設定，`warehouse_mode = \"serverless\"` 時必填，否則必須是 `null`。欄位：`db_name`（預設 `analytics`）、`base_capacity`（RPU，預設 4）、`max_capacity`（RPU 上限，預設 `null` 不設）、`usage_limit_rpu_hours`（每月 RPU 小時上限，預設 `null` 不設）、`enhanced_vpc_routing`（預設 `false`：開了要 3 個 AZ，範本的 VPC 是 2 AZ）。"
  type = object({
    db_name               = optional(string, "analytics")
    base_capacity         = optional(number, 4)
    max_capacity          = optional(number)
    usage_limit_rpu_hours = optional(number)
    enhanced_vpc_routing  = optional(bool, false)
  })
  default = null

  validation {
    condition     = (var.warehouse_mode == "serverless") == (var.serverless != null)
    error_message = "Give serverless only when warehouse_mode is serverless, and leave it null otherwise."
  }
}

variable "provisioned" {
  description = "provisioned cluster 設定，`warehouse_mode = \"provisioned\"` 時必填，否則必須是 `null`。欄位：`database_name`（預設 `analytics`）、`node_type`（預設 `ra3.large`）、`number_of_nodes`（預設 1，single-node 只收 `ra3.large`、`ra3.xlplus`）、`automated_snapshot_retention_days`（預設 7）、`skip_final_snapshot`（預設 `false`）、`multi_az`（預設 `false`）、`enhanced_vpc_routing`（預設 `false`，跟 serverless 一致）。"
  type = object({
    database_name                     = optional(string, "analytics")
    node_type                         = optional(string, "ra3.large")
    number_of_nodes                   = optional(number, 1)
    automated_snapshot_retention_days = optional(number, 7)
    skip_final_snapshot               = optional(bool, false)
    multi_az                          = optional(bool, false)
    enhanced_vpc_routing              = optional(bool, false)
  })
  default = null

  validation {
    condition     = (var.warehouse_mode == "provisioned") == (var.provisioned != null)
    error_message = "Give provisioned only when warehouse_mode is provisioned, and leave it null otherwise."
  }
}
