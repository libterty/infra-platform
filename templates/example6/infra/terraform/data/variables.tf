variable "point_in_time_recovery_days" {
  description = "point-in-time recovery 的保留天數，1–35。PITR 一律開啟。"
  type        = number
}

variable "deletion_protection" {
  description = "table 的刪除保護。destroy 之前要先改成 `false` 並 apply。"
  type        = bool
}
