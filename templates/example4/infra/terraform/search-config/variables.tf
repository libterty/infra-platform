variable "ism" {
  description = "ISM 的 index 年齡（天，從建立算起、累計，嚴格遞增）：`warm_days` 搬進 UltraWarm、`cold_days` 搬進 cold、`delete_days` 刪除；`timestamp_field` 是搬進 cold 必須的時間欄位，index template 會把它定義成 `date`。"
  type = object({
    warm_days       = number
    cold_days       = number
    delete_days     = number
    timestamp_field = string
  })
}

variable "ultrawarm_manager_role_arns" {
  description = "對應到內建 role `ultrawarm_manager` 的維運 IAM role ARN（可操作 UltraWarm 搬移）。空清單表示不建這個 mapping。"
  type        = list(string)
  default     = []
}

variable "cold_manager_role_arns" {
  description = "對應到內建 role `cold_manager` 的維運 IAM role ARN（可操作 cold storage）。空清單表示不建這個 mapping。"
  type        = list(string)
  default     = []
}

variable "read_master_secret" {
  description = "是否用 ephemeral 讀 master 帳密給 opensearch provider。這個開關只為離線的 `terraform test` 存在（測試用的 provider 不能開 ephemeral resource），測試以外一律維持預設值 `true`；dev、sit 的 tfvars 不准設成 `false`，設成 `false` 時 opensearch provider 沒有帳密，apply 會失敗。"
  type        = bool
  default     = true
  nullable    = false
}
