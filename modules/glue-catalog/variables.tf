variable "databases" {
  type = map(object({
    description  = optional(string)
    location_uri = optional(string)
  }))
  description = "要建的 Glue database，key 是 database 名稱（小寫英文字母、數字、`_`，1–255 字元；Athena 與 Redshift Spectrum 只收這種名稱），值是 `description` 與 `location_uri`（`s3://` 開頭，沒給就不設）。空的 map 不建任何東西。"

  validation {
    condition     = alltrue([for name, _ in var.databases : can(regex("^[a-z0-9_]{1,255}$", name))])
    error_message = "database names must be 1-255 chars of lowercase letters, digits and underscores."
  }

  validation {
    condition     = alltrue([for _, db in var.databases : db.location_uri == null || can(regex("^s3://[^/]", db.location_uri))])
    error_message = "location_uri must start with s3:// followed by a bucket name."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "每個 database 的 tag；`Name` 由 module 加上，值是 database 名稱。"
}
