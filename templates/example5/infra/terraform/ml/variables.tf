variable "training_schedule_state" {
  description = "每週訓練排程的狀態：`ENABLED` 或 `DISABLED`。dev 設 `DISABLED`，不必每週付訓練費（design K24）。"
  type        = string

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.training_schedule_state)
    error_message = "training_schedule_state must be ENABLED or DISABLED."
  }
}
