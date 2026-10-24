variable "tables" {
  description = "要建的 DynamoDB table，key 是 snake_case 的邏輯名稱（table 名稱是 `<project>-<env>-<key 的 _ 換成 ->`，也是 SSM key `table_<key>_arn` 的一部分）。欄位：`hash_key`、`range_key`、`attributes`（只列用在 key 的屬性）、`ttl_attribute`、`point_in_time_recovery_days`（1–35，預設 35）。一律 on-demand、CMK 加密、開刪除保護。"
  type = map(object({
    hash_key                    = string
    range_key                   = optional(string)
    attributes                  = map(string)
    ttl_attribute               = optional(string)
    point_in_time_recovery_days = optional(number, 35)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.tables) : can(regex("^[a-z][a-z0-9_]{0,30}$", k))])
    error_message = "tables keys must be snake_case (lowercase letters, digits, underscores), 1-31 chars, starting with a letter."
  }
}
